import {FieldValue} from 'firebase-admin/firestore';
import {createHash} from 'node:crypto';
import {creditRefs,reserveCredit,settleCredit,validMessage} from './translation_credits.mjs';
import {adPair,reserveAdCredit,settleAdCredit} from './ad_translation_credits.mjs';

// Credit rollout is explicitly enabled per room by the private operator.
// The result cache is server-only; each recipient can read only their paid view.
export async function processCreditTranslation(db,ref,data,room,{requestedBy,payForRecipient,provider}={}){
 if(!validMessage(data.originalText))throw Error('message_limit');
 const cid=ref.parent.parent.id,participants=room.participants??[];
 if(!participants.includes(data.senderId))throw Error('sender_not_member');
 if(requestedBy&&!participants.includes(requestedBy))throw Error('requester_not_member');
 if(payForRecipient&&requestedBy!==data.senderId)throw Error('sender_payment_not_authorized');
 if(payForRecipient&&(!participants.includes(payForRecipient)||payForRecipient===data.senderId))throw Error('invalid_credit_recipient');
 const pair=await adPair(db,participants);
 if(pair&&[...data.originalText].length>50)throw Error('ad_message_limit');
 if(pair&&payForRecipient)throw Error('ad_sponsorship_disabled');
 const blocked=[];
 for(const uid of participants.filter(uid=>uid!==data.senderId&&(!payForRecipient||uid===payForRecipient))){
  const profile=(await db.doc(`users/${uid}`).get()).data();
  const language=profile?.preferredLanguage==='Mongolian'?'mn':'ko';
  if(language===data.sourceLang)continue;
  const payer=payForRecipient?requestedBy:uid;
  const reservation=pair?await reserveAdCredit(db,{room:cid,message:ref.id,recipient:uid,sender:data.senderId,pair,language}):await reserveCredit(db,{room:cid,message:ref.id,recipient:uid,payer,language});
  const settle=pair?settleAdCredit:settleCredit;
  if(['no_credit','no_day_pass'].includes(reservation.state)){
   if(!pair)blocked.push(uid);
   else await creditRefs(db,cid,ref.id,data.senderId).access.set({status:reservation.state,language,adManaged:true,updatedAt:FieldValue.serverTimestamp()});
   continue;
  }
  if(reservation.state!=='acquired')continue;
  const cache=db.doc(`_translationCache/${createHash('sha256').update(JSON.stringify([cid,ref.id,language])).digest('hex')}`);
  let result,actualCost=0;
  try{
   result=(await cache.get()).data();
   if(!result){result=await provider(language);actualCost=result.costUsd??0;await cache.create({...result,createdAt:FieldValue.serverTimestamp()});}
  }catch(error){
   await settle(db,reservation,{error:error.message});
   continue;
  }
  // Settlement is outside the provider catch: an uncertain database commit must
  // not be mistaken for a failed translation and refunded after publication.
  await settle(db,reservation,{translation:result.translation,model:result.actualModel,costUsd:actualCost});
  if(payForRecipient)await ref.update({creditBlocked:FieldValue.arrayRemove(uid)});
  // Sender can inspect the same paid translation without a second charge.
  await creditRefs(db,cid,ref.id,data.senderId).access.set({status:'done',language,translation:result.translation,...(pair?{adManaged:true}:{}),updatedAt:FieldValue.serverTimestamp()});
 }
 await ref.update({creditManaged:true,...(pair?{adManaged:true}:{}),translationStatus:'credit_managed',...(payForRecipient?{}:{creditBlocked:blocked})});
}
