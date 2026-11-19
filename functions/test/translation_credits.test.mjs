import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {grantCredits,reserveCredit,settleCredit,validMessage} from '../worker_common/translation_credits.mjs';
import {processCreditTranslation} from '../worker_common/credit_translation_processor.mjs';
const db=new Firestore({projectId:`demo-credit-${Date.now()}`});
after(()=>db.terminate());
test('200 code points accepted; 201 and empty rejected',()=>{
 assert.ok(validMessage('가'.repeat(200)));assert.ok(validMessage('😀'.repeat(200)));
 assert.ok(!validMessage('가'.repeat(201)));assert.ok(!validMessage('😀'.repeat(201)));assert.ok(!validMessage('  '));
});
test('manual 200/500 grants are idempotent and conflicting reuse rejected',async()=>{
 await db.doc('users/grants').set({displayName:'test'});
 await grantCredits(db,{uid:'grants',amount:200,reason:'event',eventId:'one'});
 assert.equal((await grantCredits(db,{uid:'grants',amount:200,reason:'event',eventId:'one'})).duplicate,true);
 await grantCredits(db,{uid:'grants',amount:500,reason:'second',eventId:'two'});
 assert.equal((await db.doc('translationWallets/grants').get()).data().balance,700);
 await assert.rejects(grantCredits(db,{uid:'grants',amount:500,reason:'event',eventId:'one'}),/conflict/);
});
test('concurrent spending never overdraws; failure restores availability; success settles once',async()=>{
 await db.doc('users/payer').set({});await grantCredits(db,{uid:'payer',amount:1,reason:'test',eventId:'one'});
 const args={room:'r',recipient:'receiver',payer:'payer',language:'ko'};
 const results=await Promise.all(['a','b'].map(message=>reserveCredit(db,{...args,message})));
 assert.equal(results.filter(r=>r.state==='acquired').length,1);
 const won=results.find(r=>r.state==='acquired');await settleCredit(db,won,{error:'provider_failed'});
 assert.deepEqual(((await db.doc('translationWallets/payer').get()).data()),{...(await db.doc('translationWallets/payer').get()).data(),balance:1,reserved:0});
 const next=await reserveCredit(db,{...args,message:'c'});
 await settleCredit(db,next,{translation:'안녕하세요',model:'test',costUsd:0.001});
 assert.equal(await settleCredit(db,next,{translation:'duplicate'}),false);
 const wallet=(await db.doc('translationWallets/payer').get()).data();assert.equal(wallet.balance,0);assert.equal(wallet.reserved,0);
 assert.equal((await reserveCredit(db,{...args,message:'c'})).state,'done');
});
test('group cache translates once but unlocks only paid recipients; same language is free',async()=>{
 for(const [uid,language] of [['sender','Korean'],['mn1','Mongolian'],['mn2','Mongolian'],['ko','Korean'],['empty','Mongolian']])await db.doc(`users/${uid}`).set({preferredLanguage:language});
 for(const uid of ['mn1','mn2'])await grantCredits(db,{uid,amount:1,reason:'test',eventId:'one'});
 const ref=db.doc('conversations/group/messages/group-message'),data={senderId:'sender',sourceLang:'ko',originalText:'안녕'};await ref.set(data);
 let calls=0;const provider=async()=>{calls++;return {translation:'Сайн уу',actualModel:'test',costUsd:.001};};
 await processCreditTranslation(db,ref,data,{participants:['sender','mn1','mn2','ko','empty']},{provider});
 assert.equal(calls,1);assert.equal((await db.doc('translationWallets/mn1').get()).data().balance,0);assert.equal((await db.doc('translationWallets/mn2').get()).data().balance,0);
 assert.equal((await ref.collection('creditTranslations').doc('empty').get()).data().status,'no_credit');
 assert.equal((await db.doc('translationWallets/ko').get()).exists,false);
 await processCreditTranslation(db,ref,data,{participants:['sender','mn1','mn2','ko','empty']},{provider});assert.equal(calls,1);
});
test('provider failure releases reservation without debit and sponsor requires sender identity',async()=>{
 await db.doc('users/fail-receiver').set({preferredLanguage:'Mongolian'});await grantCredits(db,{uid:'fail-receiver',amount:1,reason:'test',eventId:'one'});
 const ref=db.doc('conversations/fail/messages/fail-message'),data={senderId:'sender',sourceLang:'ko',originalText:'시험'};await ref.set(data);
 const room={participants:['sender','fail-receiver']};
 await processCreditTranslation(db,ref,data,room,{provider:async()=>{throw Error('provider_failure');}});
 const w=(await db.doc('translationWallets/fail-receiver').get()).data();assert.equal(w.balance,1);assert.equal(w.reserved,0);
 await assert.rejects(processCreditTranslation(db,ref,data,room,{requestedBy:'fail-receiver',payForRecipient:'sender'}),/sender_payment_not_authorized/);
});
