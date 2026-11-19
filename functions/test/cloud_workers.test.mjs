import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore,Timestamp} from 'firebase-admin/firestore';
import {guardedTranslation,cloudProvider,processCloudMessage} from '../cloud_translation.mjs';
import {processCloudPush} from '../cloud_push.mjs';
import {dictionaryKey} from '../worker_common/translation_dictionary.mjs';
if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('emulator_required');
const db=new Firestore({projectId:'demo-cloud-workers-'+Date.now()});
after(()=>db.terminate());
test('duplicate event is processed once and failed provider is not automatically called again',async()=>{
 const ref=db.doc('conversations/r/messages/m');let calls=0;
 await Promise.all([1,2].map(()=>guardedTranslation(db,'duplicate',ref,async()=>{calls++})));
 assert.equal(calls,1);
 await assert.rejects(guardedTranslation(db,'failed',ref,async()=>{calls++;throw Error('provider_failed')}));
 await guardedTranslation(db,'failed',ref,async()=>{calls++});assert.equal(calls,2);
});
test('cloud allowance fails closed, preserves migrated usage, reserves failed attempts',async()=>{
 let calls=0;const p=cloudProvider(db,'fixture',async()=>{calls++;throw Error('provider_failed')});
 await assert.rejects(p({}),/trial_budget_limit/);assert.equal(calls,0);
 const ref=db.doc('_workerBudgets/memberCloudTrial');await ref.set({calls:199,costUsd:0.2});
 await assert.rejects(p({}),/provider_failed/);
 await assert.rejects(p({}),/trial_budget_limit/);assert.equal(calls,1);
 assert.equal((await ref.get()).data().calls,200);
});
test('cloud member combines dictionary sentences in original order without provider calls',async()=>{
 await db.doc('users/sender').set({preferredLanguage:'Korean'});await db.doc('users/recipient').set({preferredLanguage:'Mongolian'});
 const room=db.doc('conversations/plain');await room.set({participants:['sender','recipient']});
 for(const [text,translation] of [['감사합니다.','Баярлалаа.'],['조심하세요.','Болгоомжтой байгаарай.']])await db.doc('_groupTranslationDictionary/'+dictionaryKey({text,source:'ko',target:'mn'})).set({approved:true,translation});
 const ref=room.collection('messages').doc('m');await ref.set({originalText:'감사합니다. 조심하세요.',sourceLang:'ko',senderId:'sender',timestamp:Timestamp.now()});
 let calls=0;await processCloudMessage(db,ref,{providerCall:async()=>{calls++;throw Error('must_not_call')}});
 const result=(await ref.get()).data();assert.equal(calls,0);assert.equal(result.translationStatus,'done');assert.equal(result.translations.mn,'Баярлалаа. Болгоомжтой байгаарай.');
});
test('cloud push duplicate event is suppressed and no source text leaks into payload',async()=>{
 const room=db.doc('conversations/push');await room.set({participants:['sender','recipient']});
 const ref=room.collection('messages').doc('m');await ref.set({senderId:'sender',originalText:'private original',timestamp:Timestamp.now()});
 await db.doc('users/recipient/pushDevices/device').set({enabled:true,language:'ko',subscriptionJson:JSON.stringify({transport:'fcm',token:'x'.repeat(40)})});
 const sent=[];const sendNative=async x=>sent.push(x);const snapshot=await ref.get();
 await Promise.all([1,2].map(()=>processCloudPush(db,snapshot,{sendNative})));
 assert.equal(sent.length,1);assert.ok(!JSON.stringify(sent).includes('private original'));
 assert.equal((await db.collection('_pushDispatch').get()).size,1);
});
