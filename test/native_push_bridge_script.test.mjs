import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {test} from 'node:test';
import assert from 'node:assert/strict';

const dart=readFileSync(new URL('../lib/native_push_bridge_script.dart',import.meta.url),'utf8');
const nonce='page_nonce_12345678901234567890123456789';
const script=dart.match(/const _nativePushScript = r'''([\s\S]*?)''';/)[1].replace('__NONCE_JSON__',JSON.stringify(nonce));
const uid='QA_user_12345678901234567890';
function fixture(subframe=false){
  const requests=[],timers=new Map();let next=0;
  const window={tongyeokNativePushProtocolVersion:1,TongyeokNativePush:{postMessage:raw=>requests.push(JSON.parse(raw))}};
  window.top=subframe?{}:window;
  vm.runInNewContext(script,{window,setTimeout:f=>{timers.set(++next,f);return next;},clearTimeout:i=>timers.delete(i)});
  return {window,requests,timers};
}
test('out-of-order native responses settle the correct promise once',async()=>{
  const {window:w,requests:r,timers}=fixture();
  const a=w.tongyeokPushState(uid),b=w.tongyeokPushEnable(uid);
  assert.deepEqual(r.map(x=>x.action),['state','enable']);
  w.__tongyeokNativePushComplete('forged',r[0].id,'enabled',null);
  assert.equal(timers.size,2);
  w.__tongyeokNativePushComplete(nonce,r[1].id,'subscription',null);
  w.__tongyeokNativePushComplete(nonce,r[0].id,'off',null);
  assert.deepEqual(await Promise.all([a,b]),['off','subscription']);
  assert.equal(timers.size,0);
});
test('invalid identity and subframes cannot request native access',async()=>{
  const {window:w,requests}=fixture();
  await assert.rejects(w.tongyeokPushEnable('../other'),/push_failed/);
  assert.equal(requests.length,0);
  assert.equal(fixture(true).window.tongyeokPushEnable,undefined);
});
test('missing native response times out and late completion is ignored',async()=>{
  const {window:w,requests,timers}=fixture();
  const p=w.tongyeokPushDisable(uid);
  const rejected=assert.rejects(p,/push_timeout/);
  [...timers.values()][0]();
  await rejected;
  w.__tongyeokNativePushComplete(nonce,requests[0].id,'late',null);
});
test('native errors do not expose native details or login credentials',async()=>{
  const {window:w,requests}=fixture();
  const p=w.tongyeokPushEnable(uid);
  w.__tongyeokNativePushComplete(nonce,requests[0].id,null,'private native error');
  await assert.rejects(p,e=>e.message==='push_failed');
  assert.deepEqual(Object.keys(requests[0]).sort(),['action','id','nonce','uid']);
});
test('a repeated page-finished event preserves outstanding requests',async()=>{
  const {window:w,requests,timers}=fixture();
  const p=w.tongyeokPushState(uid),complete=w.__tongyeokNativePushComplete;
  vm.runInNewContext(script,{window:w,setTimeout:()=>{throw Error('unexpected replacement');},clearTimeout(){}});
  assert.equal(w.__tongyeokNativePushComplete,complete);
  complete(nonce,requests[0].id,'enabled',null);
  assert.equal(await p,'enabled');
  assert.equal(timers.size,0);
});
test('old web clients do not activate the native bridge without confirmation support',()=>{
  const window={TongyeokNativePush:{postMessage(){throw Error('must not run');}}};window.top=window;
  vm.runInNewContext(script,{window});
  assert.equal(window.tongyeokPushEnable,undefined);
});
test('confirmation is a separate request after subscription registration',async()=>{
  const {window:w,requests}=fixture();
  const p=w.tongyeokPushConfirm(uid);
  assert.equal(requests[0].action,'confirm');
  w.__tongyeokNativePushComplete(nonce,requests[0].id,'enabled',null);
  assert.equal(await p,'enabled');
});
