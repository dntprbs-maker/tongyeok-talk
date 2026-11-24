import assert from 'node:assert/strict';
import test from 'node:test';
import {exchangeMobileLogin} from './mobile-login.mjs';

const now = 1_700_000_000_000;
const uid = 'existing-wallet-and-chat-owner';
function input(signInProvider, overrides = {}) {
  return {
    method: 'POST', authorization: 'Bearer example.jwt.value',
    provider: 'apple.com', purpose: 'sign-in', now,
    verify: async () => ({uid, auth_time: now / 1000, firebase: {
      sign_in_provider: signInProvider,
      identities: {'apple.com': ['provider-subject']},
    }}),
    issue: async actualUid => {
      assert.equal(actualUid, uid);
      return 'token';
    },
    ...overrides,
  };
}

test('exchanges a recent verified social sign-in for the very same account', async () => {
  assert.deepEqual(await exchangeMobileLogin(input('apple.com')), {status: 200, body: {token: 'token'}});
  assert.equal((await exchangeMobileLogin(input('google.com', {provider: 'google.com'}))).status, 200);
});

test('linking preserves the verified legacy UID and requires the new provider', async () => {
  assert.equal((await exchangeMobileLogin(input('password', {purpose: 'start-link'}))).status, 200);
  assert.equal((await exchangeMobileLogin(input('custom', {purpose: 'finish-link'}))).status, 200);
  assert.equal((await exchangeMobileLogin(input('custom', {purpose: 'finish-link', provider: 'google.com'}))).status, 403);
  assert.equal((await exchangeMobileLogin(input('password'))).status, 403);
});

test('rejects unverified, stale, mismatched, and non-POST requests', async () => {
  assert.equal((await exchangeMobileLogin(input('apple.com', {authorization: ''}))).status, 401);
  assert.equal((await exchangeMobileLogin(input('apple.com', {now: now + 301_000}))).status, 401);
  assert.equal((await exchangeMobileLogin(input('google.com'))).status, 403);
  assert.equal((await exchangeMobileLogin(input('apple.com', {method: 'GET'}))).status, 405);
});

test('review access requires a recent password login for an allowlisted account', async () => {
  const request = {purpose: 'review-sign-in', provider: undefined};
  const review = {...request, reviewUids: new Set([uid])};
  assert.equal((await exchangeMobileLogin(input('password', review))).status, 200);
  assert.equal((await exchangeMobileLogin(input('password', request))).status, 403);
  assert.equal((await exchangeMobileLogin(input('password', {...review, reviewUids: new Set(['other'])}))).status, 403);
  for (const provider of ['apple.com', 'google.com', 'custom']) {
    assert.equal((await exchangeMobileLogin(input(provider, review))).status, 403);
  }
  assert.equal((await exchangeMobileLogin(input('password', {...review, now: now + 301_000}))).status, 401);
  assert.equal((await exchangeMobileLogin(input('password', {...review, provider: 'apple.com'}))).status, 400);
});
