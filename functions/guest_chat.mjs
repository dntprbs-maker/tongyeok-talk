// Separate guest sessions: bearer secrets never grant Firebase or history access.
import {randomBytes,createHash,timingSafeEqual} from 'node:crypto';
import {FieldValue,Timestamp} from 'firebase-admin/firestore';
export const guestSecret=()=>randomBytes(32).toString('hex');
const hash=s=>createHash('sha256').update(s).digest('hex');
const same=(a,b)=>typeof a==='string'&&typeof b==='string'&&a.length===64&&b.length===64&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const stamp=()=>FieldValue.serverTimestamp();
export const guestRef=(db,id)=>{if(!/^[a-f0-9]{40}$/.test(id??''))throw Error('invalid_request');return db.doc(`guestRooms/${id}`);};
const active=(room,now)=>room.status==='active'&&room.expiresAt.toMillis()>now;
const privateRef=(db,id)=>db.doc(`_guestSecrets/${id}`);
export function guestOpen(room,now=Date.now()){return ['waiting','active'].includes(room?.status)&&room.expiresAt?.toMillis()>now;}
export async function createGuestRoom(db,uid,{now=Date.now(),pilotOnly=false}={}){
 const profile=(await db.doc(`users/${uid}`).get()).data();
 if(!profile||profile.deleted)throw Error('unauthenticated');
 if(pilotOnly&&profile.rewardAdEnabled!==true)throw Error('pilot_only');
 // The Mongolian member sponsors BOTH directions. No day pass on the guest.
 if(profile.preferredLanguage!=='Mongolian')throw Error('mongolian_member_required');
 const id=randomBytes(20).toString('hex'),secret=guestSecret();
 await db.runTransaction(async tx=>{
  const limit=db.doc(`_guestLimits/${uid}`),old=await tx.get(limit);
  if(now-(old.data()?.createdAt?.toMillis()??0)<10000)throw Error('rate_limited');
  tx.set(limit,{createdAt:Timestamp.fromMillis(now)});
  tx.create(guestRef(db,id),{owner:uid,ownerName:profile.displayName||'회원',ownerLanguage:'mn',guestName:'',status:'waiting',createdAt:Timestamp.fromMillis(now),updatedAt:Timestamp.fromMillis(now),expiresAt:Timestamp.fromMillis(now+86400000),count:0});
  tx.create(privateRef(db,id),{inviteHash:hash(secret)});
 });
 return {id,secret};
}
export async function joinGuestRoom(db,id,{secret,name,now=Date.now()}){
 if(!/^[a-f0-9]{64}$/.test(secret??'')||typeof name!=='string'||!name.trim()||[...name].length>30)throw Error('invalid_request');
 const token=guestSecret(),room=guestRef(db,id),keys=privateRef(db,id);
 await db.runTransaction(async tx=>{
  const [r,k]=await tx.getAll(room,keys),data=r.data();
  if(!data||data.status!=='waiting'||!guestOpen(data,now)||!same(k.data()?.inviteHash,hash(secret)))throw Error('session_closed');
  const owner=await tx.get(db.doc(`users/${data.owner}`));
  if(!owner.exists||owner.data().deleted)throw Error('session_closed');
  tx.update(room,{status:'active',guestName:name.trim(),joinedAt:Timestamp.fromMillis(now),updatedAt:Timestamp.fromMillis(now)});
  tx.set(keys,{guestHash:hash(token)}); // single-use invite is consumed atomically
 });
 return {token};
}
async function authorize(db,id,{uid,token},now=Date.now(),requireActive=true){
 const ref=guestRef(db,id),room=(await ref.get()).data();
 if(!room)throw Error('session_closed');
 const profile=(await db.doc(`users/${room.owner}`).get()).data();
 if(!profile||profile.deleted)throw Error('session_closed');
 const isOwner=uid===room.owner;
 if(!isOwner){
  const keys=(await privateRef(db,id).get()).data();
  if(!/^[a-f0-9]{64}$/.test(token??'')||!same(keys?.guestHash,hash(token)))throw Error('unauthenticated');
 }
 if((requireActive&&!isOwner&&!active(room,now)))throw Error('session_closed');
 return {ref,room,isOwner};
}
export async function readGuestRoom(db,id,identity,{now=Date.now()}={}){
 const {ref,room,isOwner}=await authorize(db,id,identity,now);
 const rows=await ref.collection('messages').orderBy('createdAt').limit(200).get();
 if(!isOwner&&!active((await ref.get()).data()??{},now))throw Error('session_closed');
 const messages=rows.docs.map(doc=>{const d=doc.data();return {id:doc.id,sender:d.sender,original:d.original,source:d.source,translation:d.translation??'',status:d.status==='cloud_pending'?'pending':d.status,time:d.createdAt?.toMillis()??now};});
 return {id,ownerName:room.ownerName,guestName:room.guestName,status:guestOpen(room,now)?room.status:'ended',expiresAt:room.expiresAt.toMillis(),isOwner,messages};
}
export async function sendGuestMessage(db,id,identity,{messageId,text,now=Date.now()}){
 if(!/^[a-f0-9-]{16,64}$/.test(messageId??'')||typeof text!=='string'||!text.trim()||[...text].length>50)throw Error('invalid_request');
 const {ref,isOwner}=await authorize(db,id,identity,now),message=ref.collection('messages').doc(messageId);
 return db.runTransaction(async tx=>{
  const r=await tx.get(ref),room=r.data(),m=await tx.get(message);
  if(m.exists){if(m.data().sender!==(isOwner?'member':'guest')||m.data().original!==text.trim())throw Error('invalid_request');return {id:messageId,duplicate:true};}
  if(!active(room,now))throw Error('session_closed');
  if(room.count>=200)throw Error('session_limit');
  if(now-(room.lastSendAt?.toMillis()??0)<800)throw Error('rate_limited');
  const profile=await tx.get(db.doc(`users/${room.owner}`)),wallet=db.doc(`translationWallets/${room.owner}`),w=await tx.get(wallet);
  if(profile.data()?.deleted||profile.data()?.preferredLanguage!=='Mongolian')throw Error('session_closed');
  const lane='balance', reserved='reserved';
  const data=w.data()??{};
  if((data[lane]??0)-(data[reserved]??0)<1)throw Error('no_credit');
  tx.set(wallet,{[reserved]:(data[reserved]??0)+1,updatedAt:stamp()},{merge:true});
  const status=room.translationWorker==='cloud-trial'?'cloud_pending':'pending';
  tx.create(message,{sender:isOwner?'member':'guest',original:text.trim(),source:isOwner?'mn':'ko',status,createdAt:Timestamp.fromMillis(now),payer:room.owner,lane,reserved});
  tx.update(ref,{count:room.count+1,lastSendAt:Timestamp.fromMillis(now),updatedAt:Timestamp.fromMillis(now)});
  return {id:messageId,duplicate:false};
 });
}
export async function endGuestRoom(db,id,identity,{now=Date.now()}={}){
 const {ref}=await authorize(db,id,identity,now);
 await db.runTransaction(async tx=>{const r=await tx.get(ref);if(r.data()?.status!=='ended')tx.update(ref,{status:'ended',endedAt:Timestamp.fromMillis(now),updatedAt:Timestamp.fromMillis(now)});});
 return {status:'ended'};
}
// Only terminal messages of NEW guest rooms, acknowledged after a durable local
// write, may be removed. Existing member conversations are never touched here.
export async function acknowledgeGuestArchive(db,id,uid,ids){
 if(!Array.isArray(ids)||ids.length>200||ids.some(x=>!/^[a-f0-9-]{16,64}$/.test(x)))throw Error('invalid_request');
 const {ref,room,isOwner}=await authorize(db,id,{uid});
 if(!isOwner||guestOpen(room))throw Error('invalid_request');
 return db.runTransaction(async tx=>{
  const r=await tx.get(ref);if(guestOpen(r.data()))throw Error('invalid_request');
  const docs=ids.length?await tx.getAll(...ids.map(x=>ref.collection('messages').doc(x))):[];
  for(const d of docs)if(d.exists&&!['done','failed'].includes(d.data().status))throw Error('translation_pending');
  for(const d of docs)if(d.exists)tx.delete(d.ref);
  tx.update(ref,{archivedAt:stamp()});return {saved:ids.length};
 });
}
export async function processGuestTranslation(db,ref,provider,{cloudTrial=false,now=Date.now}={}){
 const acquired=await db.runTransaction(async tx=>{
  const data=(await tx.get(ref)).data();
  if(cloudTrial&&data?.status==='processing'&&data.cloudTrial===true){
   // Retried events may release a stale reservation, but cannot call the provider again.
   if(now()-data.processingAt.toMillis()<150000)throw Error('cloud_translation_inflight');
   return {expired:true};
  }
  if(data?.status!==(cloudTrial?'cloud_pending':'pending'))return null;
  tx.update(ref,{status:'processing',processingAt:new Date(now()),...(cloudTrial?{cloudTrial:true}:{})});
  return {data};
 });
 if(!acquired)return false;
 let result,error;
 if(acquired.expired){error='cloud_translation_expired';}
 else{
  const {original,source}=acquired.data;
  try{result=await provider({text:original,source,target:source==='ko'?'mn':'ko'});}catch(e){error=e.message;}
 }
 await db.runTransaction(async tx=>{
  const d=await tx.get(ref);if(d.data()?.status!=='processing')return;
  const m=d.data(),wallet=db.doc(`translationWallets/${m.payer}`),w=await tx.get(wallet),data=w.data()??{};
  if((data[m.reserved]??0)<1||(data[m.lane]??0)<1)throw Error('wallet_invariant');
  tx.update(wallet,{[m.reserved]:data[m.reserved]-1,[m.lane]:data[m.lane]-(result?1:0),updatedAt:new Date()});
  tx.update(ref.parent.parent,{updatedAt:new Date()});
  tx.update(ref,{status:result?'done':'failed',...(result?{translation:result.translation,model:result.actualModel}:{}),finishedAt:new Date()});
  const usage=cloudTrial&&result?{inputTokens:result.inputTokens??null,outputTokens:result.outputTokens??null,reasoningTokens:result.reasoningTokens??null}:{};
  tx.set(wallet.collection('entries').doc(`guest-${ref.parent.parent.id}-${ref.id}`),{type:result?'guest_translation':'guest_translation_failed',amount:result?-1:0,costUsd:cloudTrial?(result?.costUsd??null):(result?.costUsd??0),...usage,createdAt:new Date()});
 });
 return {success:!!result,error};
}
