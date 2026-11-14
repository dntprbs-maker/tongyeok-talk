import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, writeBatch, serverTimestamp} from 'firebase/firestore';

test('social accounts must verify their own phone before being discoverable or chatting', async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-tt-social',
    firestore: {host: '127.0.0.1', port: 8088, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')},
  });
  try {
    const phone = '+821012345678';
    const social = env.authenticatedContext('social', {email: 'social@example.test'}).firestore();
    const verified = env.authenticatedContext('social', {phone_number: phone}).firestore();
    const rival = env.authenticatedContext('rival', {phone_number: phone}).firestore();
    const contact = db => doc(db, 'users/social/private/contact');
    const directory = db => doc(db, 'phoneDirectory', phone.slice(1));
    const room = db => doc(db, 'conversations/phone-test');
    const profile = {displayName: 'Social', preferredLanguage: 'Korean', createdAt: serverTimestamp()};
    const chat = {participants: ['social', 'rival'], lastMessage: '', timestamp: serverTimestamp()};
    const data = {phoneE164: phone, phoneVerified: true};

    await assertSucceeds(setDoc(doc(social, 'users/social'), profile));
    await assertSucceeds(setDoc(doc(rival, 'users/rival'), profile));
    await assertFails(setDoc(room(social), chat));
    await assertFails(setDoc(contact(social), data));
    await assertFails(setDoc(directory(social), {uid: 'social'}));
    await assertFails(setDoc(directory(verified), {uid: 'social'}));
    await assertFails(setDoc(contact(verified), data));
    const batch = writeBatch(verified);
    batch.set(contact(verified), data);
    batch.set(directory(verified), {uid: 'social'});
    await assertSucceeds(batch.commit());
    await assertSucceeds(setDoc(room(verified), chat));
    await assertSucceeds(getDoc(directory(rival)));
    await assertFails(getDoc(contact(rival)));
    await assertFails(setDoc(directory(rival), {uid: 'rival'}));
  } finally {
    await env.cleanup();
  }
});
