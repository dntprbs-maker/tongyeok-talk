import {FieldValue} from 'firebase-admin/firestore';
import {creditRefs} from './translation_credits.mjs';
const stamp=()=>FieldValue.serverTimestamp();

// Opt in only when BOTH profiles have operator-assigned test roles.
export async function adPair(db,participants) {
 if(participants.length!==2)return null;
 const docs=await db.getAll(...participants.map(uid=>db.doc(`users/${uid}`)));
 if(docs.some(d=>d.data()?.rewardAdEnabled!==true))return null;
 const member=docs.find(d=>d.data()?.preferredLanguage==='Mongolian');
 const leader=docs.find(d=>d.data()?.preferredLanguage==='Korean');
 return member&&leader?{member:member.id,leader:leader.id}:null;
}

export async function reserveAdCredit(db,{room,message,recipient,pair,language,now=Date.now()}) {
 const refs=creditRefs(db,room,message,recipient);
 const wallet=db.doc(`translationWallets/${pair.member}`),leaderWallet=db.doc(`translationWallets/${pair.leader}`);
 const lane='balance', reserved='reserved';
 return db.runTransaction(async tx=>{
  const [c,w,l,member,leader]=await tx.getAll(refs.claim,wallet,leaderWallet,db.doc(`users/${pair.member}`),db.doc(`users/${pair.leader}`));
  if(c.exists&&['reserved','done'].includes(c.data().status))return {state:c.data().status,...refs};
  const access={language,adManaged:true,updatedAt:stamp()};
  if(member.data()?.preferredLanguage!=='Mongolian'||leader.data()?.preferredLanguage!=='Korean'||!member.data()?.rewardAdEnabled||!leader.data()?.rewardAdEnabled)throw Error('ad_pair_changed');
  if((c.data()?.attempts??0)>=3){tx.set(refs.access,{...access,status:'failed'});return {state:'failed',...refs};}
  if((l.data()?.leaderPassUntil?.toMillis?.()??0)<=now){tx.set(refs.access,{...access,status:'no_day_pass'});return {state:'no_day_pass',...refs};}
  const value=w.data()??{};
  if((value[lane]??0)-(value[reserved]??0)<1){tx.set(refs.access,{...access,status:'no_credit'});return {state:'no_credit',...refs};}
  tx.set(wallet,{[reserved]:(value[reserved]??0)+1,updatedAt:stamp()},{merge:true});
  tx.set(refs.claim,{room,message,recipient,payer:pair.member,language,lane,reserved,source:'ad-v1',status:'reserved',attempts:(c.data()?.attempts??0)+1,reservedAt:stamp()});
  tx.set(refs.access,{...access,status:'pending'});
  return {state:'acquired',...refs};
 });
}

export async function settleAdCredit(db,refs,{translation,error,model='',costUsd=0}) {
 return db.runTransaction(async tx=>{
  const claim=await tx.get(refs.claim);
  if(!claim.exists||claim.data().status!=='reserved')return false;
  const c=claim.data();
  if(c.source!=='ad-v1')throw Error('ad_claim_mismatch');
  const wallet=db.doc(`translationWallets/${c.payer}`),w=await tx.get(wallet),data=w.data();
  if((data?.[c.reserved]??0)<1||(data?.[c.lane]??0)<1)throw Error('ad_wallet_invariant');
  const success=typeof translation==='string'&&translation.length>0;
  tx.update(wallet,{[c.lane]:data[c.lane]-(success?1:0),[c.reserved]:data[c.reserved]-1,updatedAt:stamp()});
  tx.update(refs.claim,{status:success?'done':'failed',finishedAt:stamp()});
  tx.set(refs.access,{status:success?'done':'failed',adManaged:true,language:c.language,...(success?{translation,payer:c.payer,model}:{}),updatedAt:stamp()});
  tx.set(wallet.collection('entries').doc(refs.id),{type:success?'ad_translation':'ad_translation_failed',amount:success?-1:0,lane:c.lane,room:c.room,message:c.message,recipient:c.recipient,costUsd,model,...(error?{error:String(error).slice(0,120)}:{}),createdAt:stamp()});
  return true;
 });
}
