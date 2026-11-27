import assert from 'node:assert/strict';
import {test} from 'node:test';
import {recordReferralActivity} from '../referrals.mjs';

const day = 86400000;
const joined = Date.UTC(2026, 10, 1);

function fakeReferral(waitDays) {
  const referral = {activityDays: [], ...(waitDays === undefined ? {} : {waitDays})};
  const db = {
    doc: path => path,
    runTransaction: callback => callback({
      get: async path => path.startsWith('_referrals/')
        ? {data: () => referral}
        : {createTime: {toMillis: () => joined}},
      update: (path, patch) => Object.assign(referral, patch),
    }),
  };
  return {db, referral};
}

test('new referrals are due on the tenth distinct day of messaging', async () => {
  const {db, referral} = fakeReferral(0);
  for (let i = 0; i < 9; i++) {
    await recordReferralActivity(db, 'invitee', joined + day * i);
    await recordReferralActivity(db, 'invitee', joined + day * i + 1000);
  }
  assert.equal(referral.activityDays.length, 9);
  assert.equal(referral.nextCheckAt, undefined);
  await recordReferralActivity(db, 'invitee', joined + day * 9);
  assert.equal(referral.nextCheckAt.getTime(), joined + day * 9);
  await recordReferralActivity(db, 'invitee', joined + day * 10);
  assert.equal(referral.activityDays.length, 10);
  assert.equal(referral.nextCheckAt.getTime(), joined + day * 9);
});

test('previously registered referrals retain their original waiting period', async () => {
  const {db, referral} = fakeReferral();
  for (let i = 0; i < 10; i++) {
    await recordReferralActivity(db, 'invitee', joined + day * i);
  }
  assert.equal(referral.nextCheckAt.getTime(), joined + day * 30);
});
