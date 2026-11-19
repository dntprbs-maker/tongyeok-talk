import {test} from 'node:test';
import assert from 'node:assert/strict';
import {translationPolicy,koreaDay} from '../cloud_limits.mjs';
test('missing production approval retains the old allowance',()=>{
  assert.deepEqual(translationPolicy(),{mode:'legacy'});
});
test('explicit unlimited setting has no numeric cap',()=>{
  assert.deepEqual(translationPolicy({translationLimits:{mode:'unlimited'}}),{mode:'unlimited'});
});
test('future daily limits validate and can be changed independently',()=>{
  assert.deepEqual(translationPolicy({translationLimits:{mode:'daily',maxCallsPerDay:100}}),{mode:'daily',calls:100,cost:undefined});
  for(const limits of [{mode:'daily'},{mode:'daily',maxCallsPerDay:-1},{mode:'typo'}]){
    assert.throws(()=>translationPolicy({translationLimits:limits}),/invalid_translation_limits/);
  }
});
test('daily usage changes at Korean midnight',()=>{
  assert.equal(koreaDay(new Date('2026-11-20T14:59:59Z')),'2026-11-20');
  assert.equal(koreaDay(new Date('2026-11-20T15:00:00Z')),'2026-11-21');
});
