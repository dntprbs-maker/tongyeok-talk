import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../functions/package.json',import.meta.url));
const {Firestore,Timestamp}=require('@google-cloud/firestore');
import {verifyCallback,createSession,grantReward,REWARDS,TEST_UNIT,IOS_TEST_UNIT,IOS_AD_UNITS,passExpiry,midnightKst} from '../functions/rewards.mjs';
import {createServer} from 'node:http';
import {rewardHandler} from '../functions/http.mjs';
if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('emulator_required');
const db=new Firestore({projectId:`demo-ad-rewards-${Date.now()}`});
after(()=>db.terminate());
const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const getKeys=async()=>new Map([['123',publicKey]]);
function signed(event){const q=new URLSearchParams(event).toString();return q+'&signature='+sign('sha256',Buffer.from(decodeURIComponent(q)),privateKey).toString('base64url')+'&key_id=123';}
async function user(uid,role){await db.doc(`users/${uid}`).set({rewardAdEnabled:true,rewardAdRole:role,preferredLanguage:role==='member'?'Mongolian':'Korean'});}
async function prepared(uid,role,now=Date.now(),testAds=false){await user(uid,role);const s=await createSession(db,{uid,testAds},{enabled:true,localTest:testAds,now});const r=REWARDS[role];return {s,event:{ad_network:'5450213213286189855',ad_unit:testAds?TEST_UNIT:r.unit,custom_data:s.sessionId,reward_amount:String(r.amount),reward_item:r.item,timestamp:String(now),transaction_id:'txn_'+s.sessionId,user_id:uid}};}

async function iosPrepared(uid,role,now=Date.now(),testAds=false){
 await user(uid,role);
 const s=await createSession(db,{uid,testAds,platform:'ios'},{enabled:true,localTest:testAds,now,iosUnits:IOS_AD_UNITS});
 return {s,event:{ad_network:'5450213213286189855',ad_unit:s.adUnitId.split('/')[1],custom_data:s.sessionId,
  reward_amount:String(s.amount),reward_item:REWARDS[role].item,timestamp:String(now),transaction_id:'ios_'+s.sessionId,user_id:uid}};
}

test('iOS fails closed without server configuration and rejects unknown platforms',async()=>{
 await user('ios-not-configured','member');
 await assert.rejects(createSession(db,{uid:'ios-not-configured',platform:'ios'},{enabled:true}),/ios_ads_not_configured/);
 assert.equal((await db.doc('_adRewardLimits/ios-not-configured').get()).exists,false);
 await assert.rejects(createSession(db,{uid:'ios-not-configured',platform:'web'},{enabled:true}),/invalid_request/);
});

test('iOS member pins its own unit and metadata; pays 50 once without changing reserves',async()=>{
 const {s,event}=await iosPrepared('ios-member','member');
 assert.equal(s.platform,'ios');assert.equal(s.amount,50);assert.equal(s.adUnitId,IOS_AD_UNITS.member);
 await db.doc('translationWallets/ios-member').set({balance:13,reserved:2});
 await assert.rejects(grantReward(db,{...event,ad_unit:REWARDS.member.unit}),/reward_mismatch/);
 await assert.rejects(grantReward(db,{...event,reward_amount:'100'}),/reward_mismatch/);
 await assert.rejects(grantReward(db,{...event,reward_item:'other'}),/reward_mismatch/);
 assert.equal((await grantReward(db,event)).amount,50);
 assert.equal((await grantReward(db,event)).duplicate,true);
 const w=(await db.doc('translationWallets/ios-member').get()).data();
 assert.equal(w.balance,63);assert.equal(w.reserved,2);
});

test('iOS leader still needs two distinct ads for one day and rejects member unit',async()=>{
 const now=Date.now(),first=await iosPrepared('ios-leader','leader',now);
 await assert.rejects(grantReward(db,{...first.event,ad_unit:IOS_AD_UNITS.member.split('/')[1]},{now}),/reward_mismatch/);
 assert.equal((await grantReward(db,first.event,{now})).amount,0);
 const second=await iosPrepared('ios-leader','leader',now+31000);
 assert.equal((await grantReward(db,second.event,{now:now+31000})).amount,1);
 const w=(await db.doc('translationWallets/ios-leader').get()).data();
 assert.equal(w.leaderRewardAdProgress,0);assert.equal(w.leaderPassUntil.toMillis(),passExpiry(0,now+31000));
});

test('old Android pending sessions retain their original validation and 50-credit entitlement',async()=>{
 const {s,event}=await prepared('android-legacy','member');
 const ref=db.doc('_adRewardSessions/'+s.sessionId),legacy=(await ref.get()).data();
 for(const key of ['platform','expectedUnit','expectedRewardAmount','expectedRewardItem'])delete legacy[key];
 await ref.set(legacy);
 assert.equal((await grantReward(db,event)).amount,50);
 assert.equal((await db.doc('translationWallets/android-legacy').get()).data().balance,50);
});

test('iOS Google sample units cannot grant real rewards',async()=>{
 const {s,event}=await iosPrepared('ios-sample','member',Date.now(),true);
 assert.equal(s.adUnitId,'ca-app-pub-3940256099942544/'+IOS_TEST_UNIT);
 await assert.rejects(grantReward(db,event),/test_rewards_disabled/);
 assert.equal((await grantReward(db,event,{localTest:true})).amount,50);
});

test('first-party iOS HTTP session is authenticated and never accepts a client ad unit',async()=>{
 await user('ios-http','member');
 const server=createServer(rewardHandler({db,enabled:true,iosUnits:IOS_AD_UNITS,authenticate:async token=>{if(token!=='ios-fixture')throw Error();return {uid:'ios-http'};}}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try{
  const url=`http://127.0.0.1:${server.address().port}/sessions`,origin='https://dntprbs-maker.github.io';
  const preflight=await fetch(url,{method:'OPTIONS',headers:{Origin:origin}});
  assert.equal(preflight.status,204);assert.equal(preflight.headers.get('access-control-allow-origin'),origin);
  const post=(body,token='ios-fixture')=>fetch(url,{method:'POST',headers:{Origin:origin,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal((await post({platform:'ios',testAds:false},'bad')).status,401);
  assert.equal((await post({platform:'ios',adUnitId:IOS_AD_UNITS.member})).status,400);
  const response=await post({platform:'ios',testAds:false});assert.equal(response.status,200);
  const session=await response.json();assert.equal(session.adUnitId,IOS_AD_UNITS.member);assert.equal(session.amount,50);
 }finally{await new Promise(resolve=>server.close(resolve));}
});
