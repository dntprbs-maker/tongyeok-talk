const validUid=uid=>typeof uid==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(uid);
export const deletionPolicy='shared-messages-retained-v1';

export async function requestAccountDeletion(db,identity,{now=Date.now()}={}){
 if(!validUid(identity?.uid)||!Number.isFinite(identity.auth_time)||Math.abs(now-identity.auth_time*1000)>5*60000)throw Error('recent_login_required');
 const uid=identity.uid,ref=db.doc(`accountDeletionRequests/${uid}`),profile=db.doc(`users/${uid}`);
 return db.runTransaction(async tx=>{
  const [user,prior]=await tx.getAll(profile,ref);
  if(!user.exists)throw Error('profile_missing');
  if(prior.exists)return {status:prior.data().status};
  tx.create(ref,{uid,status:'requested',policy:deletionPolicy,requestedAt:new Date(now)});
  return {status:'requested'};
 });
}

// Trusted operator only. No public HTTP route calls this function. The exact
// authenticated request must already exist. Shared rooms/messages are kept.
export async function fulfillAccountDeletion(db,auth,{uid,dryRun=true}={}){
 if(!validUid(uid))throw Error('invalid_uid');
 const request=db.doc(`accountDeletionRequests/${uid}`),profile=db.doc(`users/${uid}`);
 const r=await request.get();
 if(!r.exists||r.data().uid!==uid||r.data().policy!==deletionPolicy)throw Error('authenticated_request_required');
 if(r.data().status==='completed')return {status:'completed',alreadyCompleted:true};
 if(!['requested','processing'].includes(r.data().status))throw Error('invalid_request_status');
 const [rooms,phones]=await Promise.all([
  db.collection('conversations').where('participants','array-contains',uid).get(),
  db.collection('phoneDirectory').where('uid','==',uid).get(),
 ]);
 if(dryRun)return {dryRun:true,sharedRoomsPreserved:rooms.size,phoneMappings:phones.size,policy:deletionPolicy};
 // The tombstone blocks future Firestore access even with an old ID token.
 await db.runTransaction(async tx=>{
  const current=await tx.get(request);
  if(!['requested','processing'].includes(current.data()?.status))throw Error('invalid_request_status');
  tx.set(profile,{deleted:true,deletedAt:new Date()});
  tx.update(request,{status:'processing'});
 });
 try{await auth.updateUser(uid,{disabled:true});}catch(e){if(e.code!=='auth/user-not-found')throw e;}
 // Prefixes are derived solely from the verified request owner, not input paths.
 for(const collection of await profile.listCollections())await db.recursiveDelete(collection);
 await db.recursiveDelete(db.doc(`translationWallets/${uid}`));
 for(const p of phones.docs)await db.runTransaction(async tx=>{
  const current=await tx.get(p.ref);
  if(current.data()?.uid===uid)tx.delete(p.ref);
 });
 for(const name of ['_adRewardSessions','_adRewardTransactions','_adRewardVerificationChecks']){
  while(true){
   const page=await db.collection(name).where('uid','==',uid).limit(100).get();
   if(page.empty)break;
   const batch=db.batch();for(const doc of page.docs)batch.delete(doc.ref);await batch.commit();
  }
 }
 await db.doc(`_adRewardLimits/${uid}`).delete();
 while(true){
  const page=await db.collection('userReports').where('reportedBy','==',uid).limit(100).get();
  if(page.empty)break;
  const batch=db.batch();for(const item of page.docs)batch.delete(item.ref);await batch.commit();
 }
 for(const room of rooms.docs){
  await room.ref.collection('reads').doc(uid).delete();
  for(const lane of ['translationRetries','creditRequests']){
   while(true){
    const page=await room.ref.collection(lane).where('requestedBy','==',uid).limit(100).get();
    if(page.empty)break;
    const batch=db.batch();for(const item of page.docs)batch.delete(item.ref);await batch.commit();
   }
  }
  for(const message of await room.ref.collection('messages').listDocuments())await db.recursiveDelete(message.collection('creditTranslations').doc(uid));
  // Repaint cached participant names without changing message chronology.
  await room.ref.update({participantProfileUpdatedAt:new Date()});
 }
 try{await auth.deleteUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;}
 // Keep a minimal pseudonymous receipt to make retries safe, without phone,
 // name, credentials, device tokens or a copy of the previous profile.
 await request.set({uid,status:'completed',policy:deletionPolicy,completedAt:new Date()});
 return {status:'completed',sharedRoomsPreserved:rooms.size,sharedMessagesDeleted:0};
}
