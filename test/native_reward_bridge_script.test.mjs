import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {test} from 'node:test';
import assert from 'node:assert/strict';

const dart=readFileSync(new URL('../lib/native_reward_bridge_script.dart',import.meta.url),'utf8');
const nonce='reward_page_nonce_12345678901234567890123456789';
const script=dart.match(/const _script = r'''([\s\S]*?)''';/)[1]
  .replace('__NONCE_JSON__',JSON.stringify(nonce)).replace('__TEST_MODE__','false')
  .replace('__PLATFORM__','"ios"');
const uid='QA_user_12345678901234567890';
function fixture({subframe=false,version=1}={}) {
  const requests=[],timers=new Map(),events=[];let next=0;
  const window={tongyeokNativeRewardProtocolVersion:version,
    TongyeokNativeReward:{postMessage:raw=>requests.push(JSON.parse(raw))},
    dispatchEvent:event=>events.push(event.type)};
  window.top=subframe?{}:window;
  const context={window,Event:class {constructor(type){this.type=type;}},
    setTimeout:f=>{timers.set(++next,f);return next;},clearTimeout:i=>timers.delete(i)};
  vm.runInNewContext(script,context);
  return {window,requests,timers,events,context};
}
test('bridge advertises native support only to the current web protocol and top frame',()=>{
  const f=fixture();assert.equal(f.window.tongyeokNativeRewardSupported,true);
  assert.equal(f.window.tongyeokNativeRewardTestMode,false);
  assert.equal(f.window.tongyeokNativeRewardPlatform,'ios');
  assert.deepEqual(f.events,['tongyeok-native-reward-ready']);
  assert.equal(fixture({subframe:true}).window.tongyeokRewardPrepare,undefined);
  assert.equal(fixture({version:null}).window.tongyeokRewardPrepare,undefined);
  assert.equal(fixture({version:0}).window.tongyeokRewardPrepare,undefined);
});
test('only one request runs; forged callbacks and duplicate completion cannot settle it',async()=>{
  const {window:w,requests:r,timers}=fixture();const p=w.tongyeokRewardPrepare(uid);
  await assert.rejects(w.tongyeokRewardPrepare(uid),/adUnavailable/);
  assert.equal(r.length,1);w.__tongyeokNativeRewardComplete('forged',r[0].id,'ready',null);
  assert.equal(timers.size,1);w.__tongyeokNativeRewardComplete(nonce,r[0].id,'ready',null);
  w.__tongyeokNativeRewardComplete(nonce,r[0].id,'earned',null);
  assert.equal(await p,'ready');assert.equal(timers.size,0);
});
test('show forwards only the server session fields; the result cannot write credit',async()=>{
  const {window:w,requests:r}=fixture();const id='a'.repeat(64),unit='ca-app-pub-7142914884555224/8993940063';
  const p=w.tongyeokRewardShow(uid,id,unit,false);
  assert.deepEqual(Object.keys(r[0]).sort(),['action','adUnitId','id','nonce','sessionId','testAds','uid']);
  assert.equal(r[0].sessionId,id);assert.equal(r[0].testAds,false);
  w.__tongyeokNativeRewardComplete(nonce,r[0].id,'earned',null);
  assert.equal(await p,'earned');assert.equal(w.localStorage,undefined);
});
test('native error details stay private and invalid identities cannot call the SDK',async()=>{
  const {window:w,requests:r}=fixture();await assert.rejects(w.tongyeokRewardPrepare('../user'),/adUnavailable/);
  const p=w.tongyeokRewardPrivacy(uid);w.__tongyeokNativeRewardComplete(nonce,r[0].id,null,'private SDK detail');
  await assert.rejects(p,e=>e.message==='adLoadFailed');
});
test('a timeout rejects and ignores late callbacks without retrying the ad',async()=>{
  const {window:w,requests:r,timers}=fixture();const p=w.tongyeokRewardPrepare(uid);
  const rejected=assert.rejects(p,/adLoadFailed/);[...timers.values()][0]();await rejected;
  w.__tongyeokNativeRewardComplete(nonce,r[0].id,'ready',null);assert.equal(r.length,1);
});
test('repeated page-finished events preserve the pending call and signal ready once',async()=>{
  const f=fixture(),p=f.window.tongyeokRewardPrepare(uid),callback=f.window.__tongyeokNativeRewardComplete;
  vm.runInNewContext(script,f.context);assert.equal(f.window.__tongyeokNativeRewardComplete,callback);
  assert.equal(f.events.length,1);callback(nonce,f.requests[0].id,'ready',null);assert.equal(await p,'ready');
});
