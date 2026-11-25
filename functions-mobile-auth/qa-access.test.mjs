import assert from 'node:assert/strict';
import test from 'node:test';
import {qaAccess} from './qa-access.mjs';

const config = {operator: 'owner', korean: 'test-ko', mongolian: 'test-mn'};
const owner = {uid: 'owner', email_verified: true, firebase: {
  sign_in_provider: 'custom', identities: {'google.com': ['google-owner']},
}};
const korean = {uid: 'test-ko', tongyeokQaRole: 'korean', firebase: {sign_in_provider: 'custom'}};
function call(identity, options = {}) {
  return qaAccess({
    method: 'POST', authorization: 'Bearer sample.jwt.token', config,
    purpose: 'qa-access', verify: async () => identity,
    issue: async (uid, claims) => `${uid}:${claims.tongyeokQaRole}`,
    ...options,
  });
}

test('only the verified configured Google account enters administrator mode', async () => {
  assert.deepEqual((await call(owner)).body, {role: 'administrator'});
  assert.equal((await call({...owner, uid: 'other'})).status, 403);
  assert.equal((await call({...owner, email_verified: false})).status, 403);
  assert.equal((await call({...owner, firebase: {sign_in_provider: 'password'}})).status, 403);
  assert.equal((await call(owner, {config: {...config, korean: 'owner'}})).status, 404);
});

test('test sessions switch between configured test identities only', async () => {
  const mongolian = {purpose: 'qa-switch', target: 'mongolian'};
  assert.deepEqual((await call(owner, mongolian)).body, {token: 'test-mn:mongolian'});
  assert.deepEqual((await call(korean, mongolian)).body, {token: 'test-mn:mongolian'});
  assert.equal((await call(korean, {purpose: 'qa-switch', target: 'administrator'})).status, 400);
  assert.equal((await call({...korean, tongyeokQaRole: 'mongolian'}, mongolian)).status, 403);
  assert.equal((await call(korean, {authorization: ''})).status, 401);
});
