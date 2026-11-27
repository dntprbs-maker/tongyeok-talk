import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from '@google-cloud/firestore';
import {referralStatus, registerReferral, recordReferralActivity, grantReferral} from '../functions/referrals.mjs';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('emulator_required');
const db = new Firestore({projectId:'demo-referrals'});
after(() => db.terminate());
const day = 86400000;
const baseUntil = Date.parse('2030-02-01T00:00:00+09:00');

async function profile(uid, preferredLanguage) {
  await db.doc(`users/${uid}`).set({preferredLanguage});
}

function contact(uid) {
  return db.doc(`users/${uid}/private/contact`).set({phoneVerified:false});
}

async function scenario(inviter, invitee, inviterLanguage, inviteeLanguage) {
  await profile(inviter, inviterLanguage);
  await profile(invitee, inviteeLanguage);
  await contact(inviter);
  const {code} = await referralStatus(db, inviter);
  await assert.rejects(registerReferral(db, inviter, code), /invalid_referral_code/);
  await registerReferral(db, invitee, code.toLowerCase());
  await registerReferral(db, invitee, code);
  const {writeTime} = await contact(invitee);
  const joined = writeTime.toMillis();
  const ref = db.doc(`_referrals/${invitee}`);
  await recordReferralActivity(db, invitee, joined - day);
  for (let i = 1; i <= 9; i++) await recordReferralActivity(db, invitee, joined + i * day + 1);
  await recordReferralActivity(db, invitee, joined + 3 * day + 1);
  assert.equal((await ref.get()).data().activityDays.length, 9);
  assert.equal(await grantReferral(db, ref, joined + 20 * day), false);
  const tenth = joined + 10 * day + 1;
  await recordReferralActivity(db, invitee, tenth);
  assert.equal((await ref.get()).data().activityDays.length, 10);
  assert.equal(await grantReferral(db, ref, tenth - 1), false);
  return {inviter, invitee, ref, due:tenth};
}
async function ledger(wallet) {
  const rows = await wallet.collection('entries').get();
  return rows.docs.map(doc => doc.data());
}

test('leader inviter and member invitee are both paid once in one grant', async () => {
  const {inviter, invitee, ref, due} =
    await scenario('leader-inviter', 'member-invitee', 'Korean', 'Mongolian');
  const inviterWallet = db.doc(`translationWallets/${inviter}`);
  const inviteeWallet = db.doc(`translationWallets/${invitee}`);
  await inviterWallet.set({leaderPassUntil:new Date(baseUntil), leaderRewardAdProgress:1, reserved:2});
  await inviteeWallet.set({balance:25, reserved:3, monthlyPassUntil:new Date(baseUntil)});
  const results = await Promise.all([grantReferral(db, ref, due), grantReferral(db, ref, due)]);
  assert.equal(results.filter(Boolean).length, 1);
  assert.equal(await grantReferral(db, ref, due), false);
  const leader = (await inviterWallet.get()).data();
  assert.equal(leader.leaderPassUntil.toMillis(), baseUntil + 5 * day);
  assert.equal(leader.leaderRewardAdProgress, 1);
  assert.equal(leader.reserved, 2);
  const member = (await inviteeWallet.get()).data();
  assert.equal(member.balance, 525);
  assert.equal(member.reserved, 3);
  assert.equal(member.monthlyPassUntil.toMillis(), baseUntil);
  const [leaderEntries, memberEntries] = await Promise.all([
    ledger(inviterWallet), ledger(inviteeWallet),
  ]);
  assert.equal(leaderEntries.length, 1);
  assert.equal(memberEntries.length, 1);
  assert.deepEqual(
    {kind:leaderEntries[0].kind, amount:leaderEntries[0].amount, side:leaderEntries[0].beneficiary},
    {kind:'day_pass', amount:5, side:'inviter'},
  );
  assert.deepEqual(
    {kind:memberEntries[0].kind, amount:memberEntries[0].amount, side:memberEntries[0].beneficiary},
    {kind:'translations', amount:500, side:'invitee'},
  );
  assert.equal((await referralStatus(db, inviter)).rewarded, 1);
});
test('member inviter and leader invitee are both paid once in one grant', async () => {
  const {inviter, invitee, ref, due} =
    await scenario('member-inviter', 'leader-invitee', 'Mongolian', 'Korean');
  const inviterWallet = db.doc(`translationWallets/${inviter}`);
  const inviteeWallet = db.doc(`translationWallets/${invitee}`);
  await inviterWallet.set({balance:120, reserved:7});
  await inviteeWallet.set({leaderPassUntil:new Date(baseUntil), leaderRewardAdProgress:4});
  assert.equal(await grantReferral(db, ref, due), true);
  assert.equal(await grantReferral(db, ref, due), false);
  const member = (await inviterWallet.get()).data();
  assert.equal(member.balance, 620);
  assert.equal(member.reserved, 7);
  const leader = (await inviteeWallet.get()).data();
  assert.equal(leader.leaderPassUntil.toMillis(), baseUntil + 5 * day);
  assert.equal(leader.leaderRewardAdProgress, 4);
  const [memberEntries, leaderEntries] = await Promise.all([
    ledger(inviterWallet), ledger(inviteeWallet),
  ]);
  assert.equal(memberEntries.length, 1);
  assert.deepEqual(
    {kind:memberEntries[0].kind, amount:memberEntries[0].amount, side:memberEntries[0].beneficiary},
    {kind:'translations', amount:500, side:'inviter'},
  );
  assert.equal(leaderEntries.length, 1);
  assert.deepEqual(
    {kind:leaderEntries[0].kind, amount:leaderEntries[0].amount, side:leaderEntries[0].beneficiary},
    {kind:'day_pass', amount:5, side:'invitee'},
  );
});
test('tenth different day makes it due but a repeated day never counts', async () => {
  const {invitee, ref, due} = await scenario('dup-inviter', 'dup-invitee', 'Korean', 'Mongolian');
  await recordReferralActivity(db, invitee, due + 1000);
  await recordReferralActivity(db, invitee, due + day);
  const data = (await ref.get()).data();
  assert.equal(data.activityDays.length, 10);
  assert.equal(data.nextCheckAt.toMillis(), due);
  assert.equal(await grantReferral(db, ref, due), true);
});

test('cancelled referrals are never rewarded', async () => {
  const {inviter, invitee, ref, due} = await scenario('cancel-inviter', 'cancel-invitee', 'Korean', 'Mongolian');
  await ref.update({cancelledAt:new Date(due - day)});
  assert.equal(await grantReferral(db, ref, due), false);
  assert.equal((await db.doc(`translationWallets/${inviter}`).get()).exists, false);
  assert.equal((await db.doc(`translationWallets/${invitee}`).get()).exists, false);
});