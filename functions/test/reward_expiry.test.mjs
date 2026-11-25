import assert from 'node:assert/strict';
import test from 'node:test';
import {passExpiry} from '../rewards.mjs';

const at = value => Date.parse(`2026-11-${value}+09:00`);

test('a new pass lasts until the end of the current Korean calendar day', () => {
  const midnight = at('26T00:00:00');
  assert.equal(passExpiry(0, at('25T00:00:00')), midnight);
  assert.equal(passExpiry(0, at('25T00:01:00')), midnight);
  assert.equal(passExpiry(0, at('25T23:59:59')), midnight);
  assert.equal(passExpiry(at('25T00:00:00'), at('25T17:00:00')), midnight);
  assert.equal(passExpiry(midnight, midnight), at('27T00:00:00'));
});

test('a still-active pass extends by one calendar day', () => {
  assert.equal(passExpiry(at('28T00:00:00'), at('25T17:00:00')), at('29T00:00:00'));
});
