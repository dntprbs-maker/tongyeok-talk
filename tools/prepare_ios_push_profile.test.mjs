import test from 'node:test';
import assert from 'node:assert/strict';
import {assertPushBundle,signingCertificates} from './prepare_ios_push_profile.mjs';
test('only the existing signing certificate is reused',()=>{
  const all=[{id:'other',attributes:{certificateContent:'OTHER'}},{id:'ours',attributes:{certificateContent:'OUR\nCERT'}}];
  assert.deepEqual(signingCertificates(all,['OURCERT']),[{type:'certificates',id:'ours'}]);
  assert.throws(()=>signingCertificates(all,['MISSING']));
});
test('another app or a missing Apple push capability cannot create a profile',()=>{
  const caps=[{attributes:{capabilityType:'PUSH_NOTIFICATIONS'}}];
  assert.throws(()=>assertPushBundle({attributes:{identifier:'com.other'}},caps));
  assert.throws(()=>assertPushBundle({attributes:{identifier:'com.tongyeoktalk'}},[]));
  assert.doesNotThrow(()=>assertPushBundle({attributes:{identifier:'com.tongyeoktalk'}},caps));
});
