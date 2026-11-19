import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';

// Legacy rooms keep their existing limit during the developer-only ad rollout.
export const MAX_MESSAGE_CHARACTERS=200;
export const messageLength=text=>[...text].length;
export function validMessage(text){return typeof text==='string'&&text.trim().length>0&&messageLength(text)<=MAX_MESSAGE_CHARACTERS;}
const key=value=>createHash('sha256').update(value).digest('hex');
const stamp=()=>FieldValue.serverTimestamp();
export function creditRefs(db,room,message,recipient){
 const id=key(`${room}/${message}/${recipient}`);
 return {id,claim:db.collection('_translationClaims').doc(id),access:db.doc(`conversations/${room}/messages/${message}/creditTranslations/${recipient}`)};
}
export async function grantCredits(db,{uid,amount,reason,eventId}){
 if(!uid||uid.includes('/')||!Number.isSafeInteger(amount)||amount<=0||amount>1000000||!reason?.trim()||!eventId?.trim())throw Error('invalid_credit_grant');
 const wallet=db.doc(`translationWallets/${uid}`),entry=wallet.collection('entries').doc(key(`manual:${eventId}`));
 return db.runTransaction(async tx=>{
  const [w,e,user]=await tx.getAll(wallet,entry,db.doc(`users/${uid}`));
  if(!user.exists||user.data()?.deleted===true)throw Error('credit_user_not_found');
  if(e.exists){if(e.data().amount!==amount||e.data().reason!==reason)throw Error('credit_event_conflict');return {duplicate:true,balance:w.data()?.balance??0};}
  const balance=(w.data()?.balance??0)+amount;
  tx.set(wallet,{balance,reserved:w.data()?.reserved??0,updatedAt:stamp()},{merge:true});
  tx.create(entry,{type:'grant',source:'company_manual',amount,reason,eventId,createdAt:stamp()});
  return {duplicate:false,balance};
 });
}
export async function reserveCredit(db,{room,message,recipient,payer,language}){
 const refs=creditRefs(db,room,message,recipient),wallet=db.doc(`translationWallets/${payer}`);
 return db.runTransaction(async tx=>{
  const [c,w]=await tx.getAll(refs.claim,wallet);
  if(c.exists&&['reserved','done'].includes(c.data().status))return {state:c.data().status,...refs};
  if((c.data()?.attempts??0)>=3){tx.set(refs.access,{status:'failed',language,updatedAt:stamp()});return {state:'failed',...refs};}
  const data=w.data()??{},balance=data.balance??0,reserved=data.reserved??0;
  if(balance-reserved<1){tx.set(refs.access,{status:'no_credit',language,updatedAt:stamp()});return {state:'no_credit',...refs};}
  tx.set(wallet,{balance,reserved:reserved+1,updatedAt:stamp()},{merge:true});
  tx.set(refs.claim,{room,message,recipient,payer,language,status:'reserved',attempts:(c.data()?.attempts??0)+1,reservedAt:stamp()});
  tx.set(refs.access,{status:'pending',language,updatedAt:stamp()});
  return {state:'acquired',...refs};
 });
}
export async function settleCredit(db,refs,{translation,error,costUsd=0,model=''}){
 return db.runTransaction(async tx=>{
  const claim=await tx.get(refs.claim);
  if(!claim.exists||claim.data().status!=='reserved')return false;
  const c=claim.data(),wallet=db.doc(`translationWallets/${c.payer}`),w=await tx.get(wallet),data=w.data();
  if(!data||data.reserved<1||data.balance<1)throw Error('credit_wallet_invariant');
  const success=typeof translation==='string'&&translation.length>0;
  tx.update(wallet,{balance:data.balance-(success?1:0),reserved:data.reserved-1,updatedAt:stamp()});
  tx.update(refs.claim,{status:success?'done':'failed',finishedAt:stamp()});
  tx.set(refs.access,{status:success?'done':'failed',language:c.language,...(success?{translation,payer:c.payer,model}:{}),updatedAt:stamp()});
  tx.set(wallet.collection('entries').doc(refs.id),{type:success?'translation':'translation_failed',amount:success?-1:0,room:c.room,message:c.message,recipient:c.recipient,costUsd,model,...(error?{error:String(error).slice(0,120)}:{}),createdAt:stamp()});
  return true;
 });
}
