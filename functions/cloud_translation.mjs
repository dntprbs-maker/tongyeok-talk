import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {openaiTranslationModel as model,translateWithOpenAI} from './openai_translation.mjs';
import {dictionaryProvider} from './worker_common/translation_dictionary.mjs';
import {processCreditTranslation} from './worker_common/credit_translation_processor.mjs';
import {adPair} from './worker_common/ad_translation_credits.mjs';
import {processGroupTranslation,usesGroupSplit} from './worker_common/group_translation_credits.mjs';
import {processGuestTranslation} from './guest_chat.mjs';

// Same cumulative pilot allowance as the PC worker. Bootstrap from its ledger;
// an absent budget fails closed and never silently creates a fresh allowance.
export function cloudProvider(db,apiKey,call=translateWithOpenAI) {
  return async (input,sentences) => {
    const budget=db.doc('_workerBudgets/memberCloudTrial');
    await db.runTransaction(async tx=>{
      const b=(await tx.get(budget)).data();
      if(!b||!Number.isSafeInteger(b.calls)||b.calls>=200||!(b.costUsd>=0)||b.costUsd>=0.25)throw Error('trial_budget_limit');
      tx.update(budget,{calls:b.calls+1,updatedAt:FieldValue.serverTimestamp()});
    });
    const result=await call({model,...input},{apiKey,sentences});
    if(result.actualModel!==model)throw Error('unexpected_response_model');
    await budget.update({costUsd:FieldValue.increment(result.costUsd??0),updatedAt:FieldValue.serverTimestamp()});
    return result;
  };
}

export async function processCloudMessage(db,ref,{apiKey,retry=false,creditRequest={},providerCall}={}) {
  const doc=await ref.get();if(!doc.exists)return;
  const data=doc.data();
  if(data.translationStatus==='done'||(!retry&&data.translationStatus==='credit_managed'))return;
  if(!['ko','mn'].includes(data.sourceLang)||typeof data.originalText!=='string'||!data.originalText.trim())return;
  if([...data.originalText].length>200){await ref.update({translationStatus:'failed',translationError:'message_limit'});return;}
  const roomDoc=await ref.parent.parent.get();if(!roomDoc.exists)return;
  const room=roomDoc.data();if(!(room.participants??[]).includes(data.senderId))return;
  const call=cloudProvider(db,apiKey,providerCall);
  const provider=dictionaryProvider(db,ref,call,call);
  if(usesGroupSplit(roomDoc))return processGroupTranslation(db,ref,roomDoc,provider,{providerChecksDictionary:true});
  if(room.translationCreditPolicy==='receiver-v1'||await adPair(db,room.participants??[])){
    return processCreditTranslation(db,ref,data,room,{...creditRequest,provider:target=>provider({text:data.originalText,source:data.sourceLang,target})});
  }
  const recipients=(room.participants??[]).filter(uid=>uid!==data.senderId);
  if(recipients.length){
    const profiles=await db.getAll(...recipients.map(uid=>db.doc(`users/${uid}`)));
    if(profiles.every(p=>p.data()?.preferredLanguage===(data.sourceLang==='mn'?'Mongolian':'Korean'))){
      await ref.update({translations:{[data.sourceLang]:data.originalText},translationStatus:'done',translationError:FieldValue.delete()});return;
    }
  }
  const attempt=(data.translationAttempts??0)+1;if(attempt>3)return;
  await ref.update({translationStatus:'pending',translationAttempts:attempt,translationModel:model});
  const target=data.sourceLang==='ko'?'mn':'ko';
  try{
    const result=await provider({text:data.originalText,source:data.sourceLang,target});
    await ref.update({translations:{[data.sourceLang]:data.originalText,[target]:result.translation},translationStatus:'done',translationModel:result.actualModel,translationError:FieldValue.delete(),translatedAt:FieldValue.serverTimestamp()});
  }catch(error){
    await ref.update({translationStatus:'failed',translationError:safeError(error)});
  }
}

export const safeError=e=>/^[a-z0-9_:-]{1,100}$/i.test(e?.message??'')?e.message:'translation_internal_error';

// Firestore delivers at least once. One event receipt plus a per-message lease
// prevents duplicate processing across message/retry/payment triggers.
export async function guardedTranslation(db,eventId,ref,run){
  const receipt=db.doc('_cloudTranslationEvents/'+createHash('sha256').update(eventId).digest('hex'));
  const lock=db.doc('_cloudTranslationLocks/'+createHash('sha256').update(ref.path).digest('hex'));
  const acquired=await db.runTransaction(async tx=>{
    const [r,l]=await tx.getAll(receipt,lock);
    if(r.exists)return false;
    if((l.data()?.until??0)>Date.now())throw Error('translation_busy');
    tx.create(receipt,{status:'started',createdAt:FieldValue.serverTimestamp()});
    tx.set(lock,{eventId,until:Date.now()+180000});return true;
  });
  if(!acquired)return;
  try{await run();await receipt.update({status:'done',finishedAt:FieldValue.serverTimestamp()});}
  catch(e){await receipt.update({status:'failed',error:safeError(e)});throw e;}
  finally{await lock.set({eventId,until:0});}
}

export async function processCloudGuest(db,ref,{apiKey,providerCall}={}){
  return processGuestTranslation(db,ref,cloudProvider(db,apiKey,providerCall));
}
