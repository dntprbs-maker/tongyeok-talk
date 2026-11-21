import {after, test} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from '@google-cloud/firestore';
import {processGroupTranslation, usesGroupSplit} from '../tools/group_translation_credits.mjs';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('emulator_required');
const db = new Firestore({projectId: `demo-group-${Date.now()}`});
after(() => db.terminate());

async function fixture(prefix, mongolianBalances) {
  const ko = [`${prefix}ko1`, `${prefix}ko2`];
  const mn = mongolianBalances.map((_, index) => `${prefix}mn${index}`);
  const participants = [...ko, ...mn];
  await Promise.all(participants.map(uid => db.doc(`users/${uid}`).set({
    preferredLanguage: mn.includes(uid) ? 'Mongolian' : 'Korean',
  })));
  const wallets = mn.map(uid => db.doc(`translationWallets/${uid}`));
  await Promise.all(wallets.map((ref, index) => ref.set({
    adSendCredits: mongolianBalances[index], adReceiveCredits: mongolianBalances[index],
  })));
  const roomRef = db.collection('conversations').doc(prefix);
  await roomRef.create({isGroup: true, participants});
  const room = await roomRef.get();
  assert.ok(usesGroupSplit(room));
  return {ko, mn, wallets, room};
}

async function message(room, senderId) {
  const ref = room.ref.collection('messages').doc();
  await ref.create({senderId, originalText: 'test'});
  return ref;
}

test('one Korean translation is shared and billed atomically, even with concurrent retries', async () => {
  const {ko, mn, wallets, room} = await fixture('split', [1, 1, 1]);
  const ref = await message(room, ko[0]);
  let calls = 0;
  const translate = async ({source, target}) => {
    assert.equal(source, 'ko');
    assert.equal(target, 'mn');
    calls++;
    return {translation: 'Сайн байна уу'};
  };
  await Promise.all([processGroupTranslation(db, ref, room, translate), processGroupTranslation(db, ref, room, translate)]);
  await processGroupTranslation(db, ref, room, translate);
  assert.equal(calls, 1);
  assert.equal((await ref.get()).data().translations.mn, 'Сайн байна уу');
  for (const wallet of wallets) {
    const data = (await wallet.get()).data();
    assert.equal(data.adReceiveCredits, 2 / 3);
    assert.equal(data.adReceiveReserved, 0);
  }
  assert.equal((await db.doc(`translationWallets/${ko[0]}`).get()).exists, false);
  assert.equal(mn.length, 3);
});

test('Mongolian sender pays once for both Korean recipients and failure restores the reservation', async () => {
  const {mn, wallets, room} = await fixture('sender', [1, 1]);
  const ref = await message(room, mn[0]);
  await processGroupTranslation(db, ref, room, async () => { throw new Error('provider unavailable'); });
  assert.equal((await wallets[0].get()).data().adSendCredits, 1);
  assert.equal((await wallets[0].get()).data().adSendReserved, 0);
  await processGroupTranslation(db, ref, room, async () => ({translation: '안녕하세요'}));
  assert.equal((await wallets[0].get()).data().adSendCredits, 0);
  assert.equal((await wallets[1].get()).data().adSendCredits, 1);
  assert.equal((await ref.get()).data().translations.ko, '안녕하세요');
});

test('insufficient balance does not bill or invoke the provider', async () => {
  const {ko, wallets, room} = await fixture('blocked', [1, 0]);
  const ref = await message(room, ko[0]);
  let called = false;
  await processGroupTranslation(db, ref, room, async () => { called = true; });
  assert.equal(called, false);
  assert.equal((await wallets[0].get()).data().adReceiveCredits, 1);
  assert.equal((await ref.get()).data().translationError, 'group_no_credit');
});
