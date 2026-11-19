import {getFirestore} from 'firebase-admin/firestore';
import {defineSecret} from 'firebase-functions/params';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {processCloudMessage,processCloudGuest,guardedTranslation} from './cloud_translation.mjs';
import {processCloudPush} from './cloud_push.mjs';
const PROJECT='tongyeok-talk-lab-20261024';
const key=defineSecret('TONGYEOK_OPENAI_TRANSLATION_KEY');
const vapid=defineSecret('TONGYEOK_VAPID');
const runtime={region:'asia-northeast3',serviceAccount:'tongyeok-ad-rewards@tongyeok-talk-lab-20261024.iam.gserviceaccount.com',minInstances:0,maxInstances:1,concurrency:1,memory:'256MiB',timeoutSeconds:120,retry:true};
async function ready(e){
  if(process.env.GCLOUD_PROJECT!==PROJECT||!e.data)return false;
  return (await getFirestore().doc('_workerControl/cloud').get()).data()?.enabled===true;
}
function member(e,ref,options={}){const db=getFirestore();return guardedTranslation(db,e.id,ref,()=>processCloudMessage(db,ref,{apiKey:key.value(),...options}));}
export const memberTranslation=onDocumentCreated({...runtime,secrets:[key],document:'conversations/{room}/messages/{message}'},async e=>{if(await ready(e))return member(e,e.data.ref);});
export const memberTranslationRetry=onDocumentCreated({...runtime,secrets:[key],document:'conversations/{room}/translationRetries/{request}'},async e=>{
  if(!await ready(e))return;const id=e.data.data().messageId;if(typeof id!=='string'||id.includes('/'))return;
  return member(e,e.data.ref.parent.parent.collection('messages').doc(id),{retry:true});
});
export const memberCreditRequest=onDocumentCreated({...runtime,secrets:[key],document:'conversations/{room}/creditRequests/{request}'},async e=>{
  if(!await ready(e))return;const r=e.data.data();if(typeof r.messageId!=='string'||r.messageId.includes('/'))return;
  return member(e,e.data.ref.parent.parent.collection('messages').doc(r.messageId),{retry:true,creditRequest:{requestedBy:r.requestedBy,payForRecipient:r.payForRecipient}});
});
export const guestTranslation=onDocumentCreated({...runtime,secrets:[key],document:'guestRooms/{room}/messages/{message}'},async e=>{
  if(!await ready(e)||e.data.data().status!=='pending')return;const db=getFirestore();
  return guardedTranslation(db,e.id,e.data.ref,()=>processCloudGuest(db,e.data.ref,{apiKey:key.value()}));
});
export const messagePush=onDocumentCreated({...runtime,secrets:[vapid],document:'conversations/{room}/messages/{message}'},async e=>{
  if(!await ready(e))return;
  const db=getFirestore(),control=(await db.doc('_workerControl/cloud').get()).data();
  const allowedUids=control?.pushMode==='all'?undefined:control?.pushTestUids;
  if(control?.pushMode!=='all'&&(!Array.isArray(allowedUids)||!allowedUids.length))return;
  return processCloudPush(db,e.data,{vapid:JSON.parse(vapid.value()),allowedUids});
});
