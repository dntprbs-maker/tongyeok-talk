import {test,before,after} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,collection,writeBatch,serverTimestamp,updateDoc} from 'firebase/firestore';
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
