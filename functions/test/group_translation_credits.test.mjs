import {after, test} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {groupDictionaryKey, processGroupTranslation, usesGroupSplit} from '../worker_common/group_translation_credits.mjs';
import {dictionaryKey, dictionaryProvider} from '../worker_common/translation_dictionary.mjs';

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
    balance: mongolianBalances[index],
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
  assert.deepEqual((await ref.get()).data().translations, {ko: 'test'});
  for (const uid of mn) {
    const access = await ref.collection('creditTranslations').doc(uid).get();
    assert.deepEqual(access.data(), {status:'done', translation:'Сайн байна уу'});
  }
  for (const wallet of wallets) {
    const data = (await wallet.get()).data();
    assert.equal(data.balance, 0);
    assert.equal(data.reserved, 0);
  }
  assert.equal((await db.doc(`translationWallets/${ko[0]}`).get()).exists, false);
  assert.equal(mn.length, 3);
});

test('Mongolian sender pays once for both Korean recipients and failure restores the reservation', async () => {
  const {mn, wallets, room} = await fixture('sender', [1, 1]);
  const ref = await message(room, mn[0]);
  await processGroupTranslation(db, ref, room, async () => { throw new Error('provider unavailable'); });
  assert.equal((await wallets[0].get()).data().balance, 1);
  assert.equal((await wallets[0].get()).data().reserved, 0);
  await processGroupTranslation(db, ref, room, async () => ({translation: '안녕하세요'}));
  assert.equal((await wallets[0].get()).data().balance, 0);
  assert.equal((await wallets[1].get()).data().balance, 1);
  assert.equal((await ref.get()).data().translations.ko, '안녕하세요');
});

test('insufficient recipients see only the original while funded recipients get the approved dictionary match', async () => {
  const {ko, mn, wallets, room} = await fixture('blocked', [1.5, 0.5, 0]);
  const ref = await message(room, ko[0]);
  await db.doc('_groupTranslationDictionary/'+groupDictionaryKey('ko','mn','test')).set({
    approved:true, translation:'Туршилт',
  });
  let called = false;
  await processGroupTranslation(db, ref, room, async () => { called = true; });
  assert.equal(called, false);
  assert.deepEqual((await db.getAll(...wallets)).map(wallet=>wallet.data().balance), [0.5,0.5,0]);
  assert.equal((await ref.get()).data().translationModel, 'dictionary');
  assert.deepEqual((await ref.get()).data().translations, {ko:'test'});
  const views = await db.getAll(...mn.map(uid=>ref.collection('creditTranslations').doc(uid)));
  assert.deepEqual(views.map(view=>view.data()), [
    {status:'done',translation:'Туршилт'},{status:'original_only'},{status:'original_only'},
  ]);
  const unpaid = await message(room, ko[0]);
  await processGroupTranslation(db, unpaid, room, async () => { called = true; });
  assert.equal(called, false);
  assert.equal((await unpaid.get()).data().translationStatus, 'done');
  assert.deepEqual((await db.getAll(...wallets)).map(wallet=>wallet.data().balance), [0.5,0.5,0]);
});

test('mixed sentence translation publishes one result and debits each recipient once', async () => {
  const {ko, mn, wallets, room} = await fixture('sentences', [2, 2]);
  const ref = room.ref.collection('messages').doc();
  await ref.create({senderId: ko[0], originalText: '네. 지금 오세요. 조심하세요.'});
  await db.collection('_groupTranslationDictionary')
    .doc(dictionaryKey({text: '네.', source: 'ko', target: 'mn'}))
    .set({approved: true, translation: 'Тийм.'});
  let calls = 0;
  const provider = dictionaryProvider(db, ref, async () => {
    assert.fail('unexpected single translation');
  }, async (_input, sentences) => {
    calls++;
    assert.deepEqual(sentences, ['지금 오세요.', '조심하세요.']);
    return {translations: ['Одоо ирээрэй.', 'Болгоомжтой байгаарай.'], actualModel: 'provider'};
  });
  const run = () => processGroupTranslation(db, ref, room, provider, {providerChecksDictionary: true});
  await Promise.all([run(), run()]);
  await run();
  assert.equal(calls, 1);
  for (const [i, uid] of mn.entries()) {
    const access = await ref.collection('creditTranslations').doc(uid).get();
    assert.equal(access.data().translation, 'Тийм. Одоо ирээрэй. Болгоомжтой байгаарай.');
    const wallet = (await wallets[i].get()).data();
    assert.equal(wallet.balance, 1);
    assert.equal(wallet.reserved, 0);
    assert.equal((await wallets[i].collection('entries').get()).size, 1);
  }
});
