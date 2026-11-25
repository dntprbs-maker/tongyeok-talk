import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {collection, deleteDoc, doc, getDoc, getDocs, setDoc} from 'firebase/firestore';

test('contact aliases are private, independent of profile names, and removable', async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-tt-aliases',
    firestore: {host: '127.0.0.1', port: 8088, rules: readFileSync(process.env.TONGYEOK_RULES_TEST_SOURCE ?? new URL('../firestore.rules', import.meta.url), 'utf8')},
  });
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, 'users/owner'), {displayName: 'Owner'});
      await setDoc(doc(db, 'users/peer'), {displayName: 'Original'});
    });
    const owner = env.authenticatedContext('owner').firestore();
    const peer = env.authenticatedContext('peer').firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const alias = db => doc(db, 'users/owner/contactAliases/peer');
    await assertSucceeds(setDoc(alias(owner), {alias: '현장 팀장님'}));
    assert.equal((await assertSucceeds(getDoc(alias(owner)))).data().alias, '현장 팀장님');
    await assertSucceeds(getDocs(collection(owner, 'users/owner/contactAliases')));
    await assertFails(getDoc(alias(peer)));
    await assertFails(getDocs(collection(peer, 'users/owner/contactAliases')));
    await assertFails(getDoc(alias(anonymous)));
    await assertFails(deleteDoc(alias(peer)));
    await assertFails(setDoc(alias(peer), {alias: 'Changed'}));
    await assertFails(setDoc(alias(owner), {alias: 'A\nB'}));
    await assertFails(setDoc(alias(owner), {alias: 'x'.repeat(61)}));
    await assertFails(setDoc(alias(owner), {alias: 'Name', displayName: 'Bad'}));
    await assertSucceeds(setDoc(alias(owner), {alias: 'Шинэ хоч'}));
    assert.equal((await getDoc(alias(owner))).data().alias, 'Шинэ хоч');
    assert.equal((await getDoc(doc(peer, 'users/peer'))).data().displayName, 'Original');
    await assertSucceeds(deleteDoc(alias(owner)));
    assert.equal((await getDoc(alias(owner))).exists(), false);
  } finally {
    await env.cleanup();
  }
});
