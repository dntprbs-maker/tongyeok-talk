import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, writeBatch, serverTimestamp} from 'firebase/firestore';

test('social accounts must register a phone before being discoverable or chatting', async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-tt-social',
    firestore: {host: '127.0.0.1', port: 8088, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')},
  });
  try {
    const phone = '+821012345678';
    const social = env.authenticatedContext('social', {firebase: {sign_in_provider: 'google.com'}}).firestore();
    const rival = env.authenticatedContext('rival', {firebase: {sign_in_provider: 'apple.com'}}).firestore();
    const contact = db => doc(db, 'users/social/private/contact');
    const directory = db => doc(db, 'phoneDirectory', phone.slice(1));
    const room = db => doc(db, 'conversations/phone-test');
    const profile = {displayName: 'Social', preferredLanguage: 'Korean', createdAt: serverTimestamp()};
    const chat = {participants: ['social', 'rival'], lastMessage: '', timestamp: serverTimestamp()};
    const data = {phoneE164: phone, phoneVerified: false};

    await assertSucceeds(setDoc(doc(social, 'users/social'), profile));
    await assertSucceeds(setDoc(doc(rival, 'users/rival'), profile));
    await assertFails(setDoc(room(social), chat));
    await assertFails(setDoc(contact(social), data));
    await assertFails(setDoc(contact(social), {...data, phoneVerified: true}));
    await assertFails(setDoc(directory(social), {uid: 'social'}));
    const batch = writeBatch(social);
    batch.set(contact(social), data);
    batch.set(directory(social), {uid: 'social'});
    await assertSucceeds(batch.commit());
    await assertSucceeds(setDoc(room(social), chat));
    await assertSucceeds(getDoc(directory(rival)));
    await assertFails(getDoc(contact(rival)));
    await assertFails(setDoc(directory(rival), {uid: 'rival'}));
    const otherNumber = '97699112233';
    const appleBatch = writeBatch(rival);
    appleBatch.set(doc(rival, 'users/rival/private/contact'), {
      phoneE164: '+' + otherNumber, phoneVerified: false,
    });
    appleBatch.set(doc(rival, 'phoneDirectory/' + otherNumber), {uid: 'rival'});
    await assertSucceeds(appleBatch.commit());
    const webLookup = await assertSucceeds(getDoc(doc(social, 'phoneDirectory/' + otherNumber)));
    const iosLookup = await assertSucceeds(getDoc(directory(rival)));
    if (webLookup.data().uid !== 'rival' || iosLookup.data().uid !== 'social') {
      throw new Error('Cross-platform number lookup mismatch');
    }
    for (const [sender, receiver, uid, locale] of [
      [social, rival, 'social', 'ko'],
      [rival, social, 'rival', 'mn'],
    ]) {
      const message = db => doc(db, 'conversations/phone-test/messages/' + uid);
      await assertSucceeds(setDoc(message(sender), {
        senderId: uid, originalText: 'Test', sourceLang: locale,
        translations: {}, timestamp: serverTimestamp(),
      }));
      const received = await assertSucceeds(getDoc(message(receiver)));
      if (received.data().senderId !== uid) throw new Error('Message delivery mismatch');
    }
  } finally {
    await env.cleanup();
  }
});
