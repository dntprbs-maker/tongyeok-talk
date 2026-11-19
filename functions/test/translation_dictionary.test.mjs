import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {Firestore} from 'firebase-admin/firestore';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc, getDoc, serverTimestamp, setDoc} from 'firebase/firestore';
import {dictionaryKey, dictionaryProvider} from '../worker_common/translation_dictionary.mjs';
import {openaiTranslationModel, translateWithOpenAI} from '../openai_translation.mjs';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('emulator_required');
const projectId = 'demo-tongyeok-dictionary';

test('member messages use zero or one request and preserve order, decimal points and whole-message corrections', async t => {
  const db = new Firestore({projectId: 'demo-tongyeok-sentences'});
  t.after(() => db.terminate());
  const collection = db.collection('_groupTranslationDictionary');
  const input = {text: '고맙습니다. 내일 9.5에 와 주세요. 조심하세요.', source: 'ko', target: 'mn'};
  const pieces = ['고맙습니다.', '내일 9.5에 와 주세요.', '조심하세요.'];
  const output = ['Баярлалаа.', 'Маргааш 9.5-д ирээрэй.', 'Болгоомжтой байгаарай.'];
  const entry = text => collection.doc(dictionaryKey({...input, text}));
  const messages = db.collection('conversations').doc().collection('messages');
  const requested = [];
  const fetcher = async (_url, {body}) => {
    const {input, text} = JSON.parse(body);
    const segments = JSON.parse(input);
    assert.deepEqual(text.format.schema.required, segments.map(({id}) => String(id)));
    requested.push(segments.map(({text}) => text));
    return Response.json({status: 'completed', model: openaiTranslationModel,
      output: [{type: 'message', role: 'assistant', content: [{type: 'output_text',
        text: JSON.stringify(Object.fromEntries(segments.reverse().map(({id, text}) =>
          [id, output[pieces.indexOf(text)]]))),
      }]}]});
  };
  const single = async ({text}) => {
    requested.push([text]);
    return {translation: output[pieces.indexOf(text)] ?? 'Бүтэн зурвас.', actualModel: 'provider'};
  };
  const batch = (input, sentences) => translateWithOpenAI(input, {sentences, apiKey: 'test', fetcher});
  const ref = messages.doc();
  const translate = dictionaryProvider(db, ref, single, batch);

  assert.equal((await translate(input)).translation, output.join(' '));
  assert.deepEqual(requested.splice(0), [pieces]);
  await translate(input);
  assert.deepEqual(requested.splice(0), [pieces]);
  assert.equal((await entry(pieces[1]).get()).data().count, 1);

  await entry(pieces[0]).set({approved: true, translation: output[0]});
  assert.equal((await translate(input)).translation, output.join(' '));
  assert.deepEqual(requested.splice(0), [pieces.slice(1)]);
  await entry(pieces[2]).set({approved: true, translation: output[2]});
  assert.equal((await translate(input)).translation, output.join(' '));
  assert.deepEqual(requested.splice(0), [[pieces[1]]]);
  await entry(pieces[1]).set({approved: true, translation: output[1]});
  assert.equal((await translate(input)).translation, output.join(' '));
  assert.deepEqual(requested, []);

  await entry(input.text).set({approved: true, translation: 'Хянасан орчуулга.'});
  assert.equal((await translate(input)).translation, 'Хянасан орчуулга.');
  assert.deepEqual(requested, []);
  const ambiguous = 'Dr. Kim. 내일 방문해 주세요.';
  assert.equal((await translate({...input, text: ambiguous})).translation, 'Бүтэн зурвас.');
  assert.deepEqual(requested, [[ambiguous]]);
});

test('split sentences count ten distinct messages in their own direction', async t => {
  const db = new Firestore({projectId: 'demo-tongyeok-sentence-count'});
  t.after(() => db.terminate());
  const messages = db.collection('conversations').doc().collection('messages');
  const input = {text: 'Баярлалаа. Маргааш ирээрэй. Баярлалаа.', source: 'mn', target: 'ko'};
  const dictionary = db.collection('_groupTranslationDictionary');
  const entry = dictionary.doc(dictionaryKey({...input, text: 'Баярлалаа.'}));
  const reverse = dictionary.doc(dictionaryKey({text: 'Баярлалаа.', source: 'ko', target: 'mn'}));
  const single = async () => { throw Error('unexpected single call'); };
  const batch = async (_input, sentences) => {
    assert.deepEqual(sentences, ['Баярлалаа.', 'Маргааш ирээрэй.']);
    return {translations: ['감사합니다.', '내일 오세요.'], actualModel: 'provider'};
  };
  for (let n = 0; n < 10; n++) {
    const process = dictionaryProvider(db, messages.doc(String(n)), single, batch);
    assert.equal((await process(input)).translation, '감사합니다. 내일 오세요. 감사합니다.');
    if (n < 9) await process(input);
    assert.equal((await entry.get()).data().count, n + 1);
  }
  assert.equal((await entry.get()).data().approved, true);
  assert.equal((await reverse.get()).exists, false);
  const result = await dictionaryProvider(db, messages.doc('next'), single, batch)(input);
  assert.equal(result.actualModel, 'dictionary');
});

test('the tenth distinct translation registers a dictionary entry', async () => {
  const db = new Firestore({projectId});
  try {
    const input = {text: ' 감사합니다. ', source: 'ko', target: 'mn'};
    const entry = db.collection('_groupTranslationDictionary').doc(dictionaryKey(input));
    await entry.delete();
    const room = db.collection('conversations').doc();
    let calls = 0;
    const provider = async () => {
      calls++;
      return {translation: 'Баярлалаа.', actualModel: 'provider'};
    };
    const messages = room.collection('messages');
    for (let i = 0; i < 9; i++) {
      await dictionaryProvider(db, messages.doc(String(i)), provider)(input);
    }
    await dictionaryProvider(db, messages.doc('8'), provider)(input);
    assert.equal((await entry.get()).data().count, 9);
    await dictionaryProvider(db, messages.doc('9'), provider)(input);
    assert.equal((await entry.get()).data().count, 10);
    const result = await dictionaryProvider(db, messages.doc('10'), provider)(
      {...input, text: input.text.trim()},
    );
    assert.equal(calls, 11);
    assert.deepEqual(result, {translation: 'Баярлалаа.', actualModel: 'dictionary', costUsd: 0});
  } finally {
    await db.terminate();
  }
});

test('only a member can report the actual translation once under their own UID', async () => {
  const env = await initializeTestEnvironment({projectId, firestore: {
    rules: readFileSync(new URL('../../firestore.cloud-test.rules', import.meta.url), 'utf8'),
  }});
  const room = 'conversations/report-test';
  const message = room + '/messages/example';
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, room), {participants: ['reader', 'sender']});
      await setDoc(doc(db, message), {sourceLang: 'ko', originalText: '네.',
        translationStatus: 'credit_managed'});
      await setDoc(doc(db, message + '/creditTranslations/reader'),
        {status: 'done', translation: 'Тийм ээ.'});
    });
    const reader = env.authenticatedContext('reader').firestore();
    const sender = env.authenticatedContext('sender').firestore();
    const outsider = env.authenticatedContext('outsider').firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const report = message + '/translationReports/reader';
    const record = {source: 'ko', target: 'mn', original: '네.',
      translation: 'Тийм ээ.', createdAt: serverTimestamp()};
    await assertFails(setDoc(doc(reader, report), {...record, translation: '변조'}));
    await assertFails(setDoc(doc(outsider, message + '/translationReports/outsider'), record));
    await assertSucceeds(setDoc(doc(reader, report), record));
    await assertFails(setDoc(doc(reader, report), record));
    await assertSucceeds(getDoc(doc(reader, report)));
    await assertFails(getDoc(doc(sender, report)));
    await assertFails(getDoc(doc(outsider, report)));
    await assertFails(getDoc(doc(anonymous, report)));
    await assertSucceeds(getDoc(doc(reader, message)));
    await assertFails(getDoc(doc(outsider, message)));
    await assertFails(getDoc(doc(anonymous, message)));
    const dictionary = '_groupTranslationDictionary/example';
    await assertFails(getDoc(doc(reader, dictionary)));
    await assertFails(setDoc(doc(reader, dictionary), {approved: true, translation: '위조'}));
  } finally {
    await env.cleanup();
  }
});
