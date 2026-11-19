import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from '../node_modules/firebase-admin/lib/esm/app/index.js';
import {getFirestore} from '../node_modules/firebase-admin/lib/esm/firestore/index.js';
import {createGuestRoom,joinGuestRoom,sendGuestMessage,readGuestRoom,endGuestRoom,processGuestTranslation,acknowledgeGuestArchive} from '../guest_chat.mjs';
import {guestPage} from '../guest_page.mjs';
import {processCloudGuestEvent} from '../guest_cloud_translation.mjs';
import vm from 'node:vm';
let db,app,room,token;
const now=Date.now(),uid='guest-owner';
before(async()=>{process.env.FIRESTORE_EMULATOR_HOST??='127.0.0.1:8088';app=initializeApp({projectId:'demo-guest-'+now});db=getFirestore(app);await db.doc('users/'+uid).set({displayName:'시험 회원',preferredLanguage:'Mongolian',rewardAdEnabled:true});await db.doc('translationWallets/'+uid).set({balance:4});});
after(async()=>{await db.terminate();await deleteApp(app);});
test('guest page compiles and is free of login/ad/history interfaces',()=>{
 new vm.Script(guestPage.match(/<script>([\s\S]*)<\/script>/)[1]);
 assert(!guestPage.includes('firebasejs'));assert(guestPage.includes('textContent'));assert(guestPage.includes('sessionStorage'));assert(!guestPage.includes('localStorage'));
});
test('invite is one-time, secrets not in room summary; only Mongolian member sponsors',async()=>{
 await db.doc('users/korean').set({preferredLanguage:'Korean'});
 await assert.rejects(createGuestRoom(db,'korean',{now}),/mongolian_member_required/);
 room=await createGuestRoom(db,uid,{now});const summary=(await db.doc('guestRooms/'+room.id).get()).data();assert(!JSON.stringify(summary).includes(room.secret));
 await assert.rejects(joinGuestRoom(db,room.id,{secret:'a'.repeat(64),name:'방문자',now}),/session_closed/);
 token=(await joinGuestRoom(db,room.id,{secret:room.secret,name:'방문자',now})).token;
 await assert.rejects(joinGuestRoom(db,room.id,{secret:room.secret,name:'다른 방문자',now}),/session_closed/);
 await assert.rejects(readGuestRoom(db,room.id,{uid:'outsider'}),/unauthenticated/);
});
test('both directions reserve and charge only owner wallet; duplicates never charge twice',async()=>{
 const mid='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',gid='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
 await sendGuestMessage(db,room.id,{uid},{messageId:mid,text:'Сайн байна уу',now:now+1000});
 await sendGuestMessage(db,room.id,{uid},{messageId:mid,text:'Сайн байна уу',now:now+1000});
 const ref=db.doc(`guestRooms/${room.id}/messages/${mid}`);let calls=0;
 await processGuestTranslation(db,ref,async()=>{calls++;return {translation:'안녕하세요',actualModel:'fixture',costUsd:0};});
 await processGuestTranslation(db,ref,async()=>{calls++;throw Error('never');});assert.equal(calls,1);
 await sendGuestMessage(db,room.id,{token},{messageId:gid,text:'안녕하세요',now:now+2000});
 await processGuestTranslation(db,db.doc(`guestRooms/${room.id}/messages/${gid}`),async()=>({translation:'Сайн байна уу',actualModel:'fixture',costUsd:0}));
 const wallet=(await db.doc('translationWallets/'+uid).get()).data();assert.equal(wallet.balance,2);assert.equal(wallet.reserved,0);
 assert.equal((await readGuestRoom(db,room.id,{token})).messages.length,2);
});
test('failure refunds reservation; length/role spoof/empty credit rejected',async()=>{
 await assert.rejects(sendGuestMessage(db,room.id,{token},{messageId:'cccccccccccccccccccccccccccccccc',text:'가'.repeat(51),now:now+3000}),/invalid_request/);
 const ref=db.doc(`guestRooms/${room.id}/messages/dddddddddddddddddddddddddddddddd`);
 await sendGuestMessage(db,room.id,{token},{messageId:ref.id,text:'실패 시험',now:now+3000});
 await processGuestTranslation(db,ref,async()=>{throw Error('provider_down');});
 const w=(await db.doc('translationWallets/'+uid).get()).data();assert.equal(w.balance,2);assert.equal(w.reserved,0);
 await assert.rejects(acknowledgeGuestArchive(db,room.id,uid,['dddddddddddddddddddddddddddddddd']),/invalid_request/);
});
test('ending denies old guest credentials/history and invite replay; only owner can archive',async()=>{
 await endGuestRoom(db,room.id,{token});
 await assert.rejects(readGuestRoom(db,room.id,{token}),/session_closed/);
 await assert.rejects(sendGuestMessage(db,room.id,{token},{messageId:'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',text:'다시',now:now+4000}),/session_closed/);
 const saved=await readGuestRoom(db,room.id,{uid});assert.equal(saved.messages.length,3);
 await assert.rejects(acknowledgeGuestArchive(db,room.id,'outsider',saved.messages.map(x=>x.id)),/unauthenticated/);
 await acknowledgeGuestArchive(db,room.id,uid,saved.messages.map(x=>x.id));
 assert.equal((await readGuestRoom(db,room.id,{uid})).messages.length,0);
 await assert.rejects(joinGuestRoom(db,room.id,{secret:room.secret,name:'재입장',now:now+5000}),/session_closed/);
});

test('cloud trial ignores ordinary messages, consumes one credit on replay, and releases failed or expired holds',async()=>{
 const owner='cloud-trial-owner',budget=db.doc('_workerBudgets/guestCloudTrial');
 const wallet=db.doc(`translationWallets/${owner}`);
 await db.doc(`users/${owner}`).set({preferredLanguage:'Mongolian',rewardAdEnabled:true});
 await wallet.set({balance:4});
 const start=Date.now(),invite=await createGuestRoom(db,owner,{now:start});
 const roomRef=db.doc(`guestRooms/${invite.id}`);
 const {token:guestToken}=await joinGuestRoom(db,invite.id,{secret:invite.secret,name:'시험',now:start});
 async function send(hex,identity,text,offset){
  const messageId=hex.repeat(32);
  await sendGuestMessage(db,invite.id,identity,{messageId,text,now:start+offset});
  return roomRef.collection('messages').doc(messageId);
 }
 const normal=await send('1',{uid:owner},'Сайн уу',1000);
 let calls=0;
 const fixture={apiKey:'emulator-only',call:async({model})=>{
  calls++;
  return {translation:'안녕하세요',actualModel:model,costUsd:0};
 }};
 assert.equal(await processCloudGuestEvent(db,await normal.get(),fixture),false);
 assert.equal(calls,0);
 await processGuestTranslation(db,normal,async()=>{throw Error('test_cleanup');});

 await roomRef.update({translationWorker:'cloud-trial'});
 const marked=await send('2',{uid:owner},'Сайн байна уу',2000);
 const event=await marked.get();
 assert.equal((await readGuestRoom(db,invite.id,{uid:owner})).messages.at(-1).status,'pending');
 assert.equal(await processGuestTranslation(db,marked,fixture.call),false);
 const concurrent=await Promise.allSettled([processCloudGuestEvent(db,event,fixture),processCloudGuestEvent(db,event,fixture)]);
 assert(concurrent.some(result=>result.status==='fulfilled'&&result.value?.success));
 assert.equal(await processCloudGuestEvent(db,event,fixture),false);
 assert.equal(calls,1);
 assert.equal((await budget.get()).data().calls,1);
 assert.equal((await wallet.get()).data().balance,3);
 assert.equal((await wallet.get()).data().reserved,0);

 await budget.update({calls:12});
 const blocked=await send('3',{token:guestToken},'한도 시험',3000);
 const limited=await processCloudGuestEvent(db,await blocked.get(),fixture);
 assert.equal(limited.error,'cloud_translation_budget_limit');
 assert.equal((await blocked.get()).data().status,'failed');
 const stale=await send('4',{token:guestToken},'복구 시험',4000);
 const originalEvent=await stale.get();
 await stale.update({status:'processing',cloudTrial:true,processingAt:new Date(Date.now()-151000)});
 assert.equal((await processCloudGuestEvent(db,originalEvent,fixture)).error,'cloud_translation_expired');
 assert.equal((await stale.get()).data().status,'failed');
 assert.equal(calls,1);
 assert.equal((await wallet.get()).data().balance,3);
 assert.equal((await wallet.get()).data().reserved,0);
});
