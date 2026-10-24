import {test,before,after} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,collection,writeBatch,serverTimestamp,updateDoc,Timestamp,query,where,orderBy,startAfter} from 'firebase/firestore';
let env,a,b;
before(async()=>{
 env=await initializeTestEnvironment({projectId:`demo-tt-phone-${Date.now().toString(36)}`,
  firestore:{host:'127.0.0.1',port:8088,rules:readFileSync('firestore.rules','utf8')}});
 a=env.authenticatedContext('alpha',{email:'p821000001111@phone.tongyeok.invalid'}).firestore();
 b=env.authenticatedContext('beta',{email:'p97610002222@phone.tongyeok.invalid'}).firestore();
});
after(async()=>{await env?.cleanup();});
test('atomic own phone registration and exact lookup',async()=>{
 const batch=writeBatch(a);
 batch.set(doc(a,'users/alpha'),{displayName:'시험 사용자',preferredLanguage:'Korean',createdAt:serverTimestamp()});
 batch.set(doc(a,'phoneDirectory/821000001111'),{uid:'alpha'});
 batch.set(doc(a,'users/alpha/private/contact'),{phoneE164:'+821000001111',phoneVerified:false});
 await assertSucceeds(batch.commit());
 await assertSucceeds(getDoc(doc(b,'phoneDirectory/821000001111')));
 await assertSucceeds(getDoc(doc(a,'users/alpha/private/contact')));
});
test('phone and profile directories cannot be listed',async()=>{
 await assertFails(getDocs(collection(b,'phoneDirectory')));
 await assertFails(getDocs(collection(b,'users')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'users/alpha')));
});
test('another user cannot read private phone or claim its mapping',async()=>{
 await assertFails(getDoc(doc(b,'users/alpha/private/contact')));
 await assertFails(setDoc(doc(b,'phoneDirectory/821000001111'),{uid:'beta'}));
 await assertFails(setDoc(doc(a,'phoneDirectory/97610002222'),{uid:'alpha'}));
});
test('SMS verification cannot be forged and only two profile languages are accepted',async()=>{
 await assertFails(updateDoc(doc(a,'users/alpha/private/contact'),{phoneVerified:true}));
 await assertFails(updateDoc(doc(a,'users/alpha'),{preferredLanguage:'English'}));
 await assertSucceeds(updateDoc(doc(a,'users/alpha'),{preferredLanguage:'Mongolian'}));
});

test('receipts visible only to room members, monotonic, and count incoming messages',async()=>{
 const room=doc(a,'conversations/unread');
 await setDoc(room,{participants:['alpha','beta'],lastMessage:'',timestamp:serverTimestamp()});
 const send=async(db,id,sender,text)=>{const batch=writeBatch(db);batch.set(doc(db,'conversations/unread/messages/'+id),{senderId:sender,originalText:text,translations:{},sourceLang:'ko',timestamp:serverTimestamp()});batch.update(doc(db,'conversations/unread'),{lastMessage:text,timestamp:serverTimestamp()});await batch.commit();};
 await send(a,'one','alpha','first'); await send(b,'own','beta','own'); await send(a,'two','alpha','second');
 const list=collection(b,'conversations/unread/messages');
 let pending=await getDocs(query(list,orderBy('timestamp')));
 if(pending.docs.filter(d=>d.data().senderId!=='beta').length!==2)throw Error('incoming count mismatch');
 const through=pending.docs.at(-1).data().timestamp,receipt=doc(b,'conversations/unread/reads/beta');
 await assertSucceeds(setDoc(receipt,{readThrough:through}));
 await assertSucceeds(getDoc(doc(a,'conversations/unread/reads/beta')));
 await assertFails(setDoc(doc(a,'conversations/unread/reads/beta'),{readThrough:through}));
 await assertFails(setDoc(receipt,{readThrough:Timestamp.fromMillis(1)}));
 await assertFails(setDoc(receipt,{readThrough:Timestamp.fromMillis(Date.now()+86400000)}));
 await send(a,'three','alpha','new after reading');
 pending=await getDocs(query(list,orderBy('timestamp'),startAfter(through)));
 if(pending.docs.filter(d=>d.data().senderId!=='beta').length!==1)throw Error('new arrival lost');
 await assertFails(getDoc(doc(env.authenticatedContext('stranger').firestore(),'conversations/unread/reads/stranger')));
});
test('push subscription is owner-only and cannot be listed or forged for others',async()=>{
 const data={subscriptionJson:'{"endpoint":"https://fcm.googleapis.com/test"}',enabled:true,language:'ko',updatedAt:serverTimestamp()};
 await assertSucceeds(setDoc(doc(a,'users/alpha/pushDevices/device-one'),data));
 await assertSucceeds(getDoc(doc(a,'users/alpha/pushDevices/device-one')));
 await assertFails(getDoc(doc(b,'users/alpha/pushDevices/device-one')));
 await assertFails(getDocs(collection(a,'users/alpha/pushDevices')));
 await assertFails(setDoc(doc(b,'users/alpha/pushDevices/device-two'),data));
 await assertFails(setDoc(doc(a,'users/alpha/pushDevices/bad'),{...data,language:'en'}));
 await assertFails(setDoc(doc(a,'_pushDispatch/forged'),{status:'sent'}));
});
test('translation output cannot be forged, retries require membership and failed status',async()=>{
 const path='conversations/unread/messages/two';
 await assertFails(updateDoc(doc(a,path),{translations:{mn:'forged'},translationStatus:'done'}));
 const retry={messageId:'two',requestedBy:'alpha',requestedAt:serverTimestamp()};
 await assertSucceeds(setDoc(doc(a,'conversations/unread/translationRetries/legacy'),{...retry,messageId:'one'}));
 await env.withSecurityRulesDisabled(async(context)=>{await updateDoc(doc(context.firestore(),path),{translationStatus:'failed'});});
 await assertSucceeds(setDoc(doc(a,'conversations/unread/translationRetries/request-one'),retry));
 await assertFails(setDoc(doc(b,'conversations/unread/translationRetries/forged'),retry));
 await assertFails(setDoc(doc(env.authenticatedContext('stranger').firestore(),'conversations/unread/translationRetries/outsider'),{...retry,requestedBy:'stranger'}));
 await assertFails(getDocs(collection(env.authenticatedContext('stranger').firestore(),'conversations/unread/messages')));
});
