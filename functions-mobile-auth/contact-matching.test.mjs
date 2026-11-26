import assert from 'node:assert/strict';
import {test} from 'node:test';
import {matchContactNumbers} from './contact-matching.mjs';

function firestore(records, senders) {
  return {
    doc(path) {
      return {
        path,
        collection(name) {
          assert.equal(name, 'messages');
          return {where(field, operator, peer) {
            assert.equal(field, 'senderId');
            assert.equal(operator, '==');
            return {limit(count) {
              assert.equal(count, 1);
              return {get: async () => ({empty: !senders[path]?.includes(peer)})};
            }};
          }};
        },
      };
    },
    getAll: async (...refs) => refs.map(ref => ({
      ref,
      exists: ref.path in records,
      data: () => records[ref.path],
    })),
  };
}

test('only consenting, participating direct contacts can provide a match', async () => {
  const room = 'conversations/existing';
  const peer = 'users/peer';
  const consent = peer + '/private/contactMatchConsent';
  const contact = peer + '/private/contact';
  const phone = '+821012345678';
  const data = {
    [room]: {participants: ['viewer', 'peer']},
    [peer]: {displayName: 'Example'},
    [consent]: {enabled: true},
    [contact]: {phoneE164: phone},
  };
  const senders = {[room]: ['peer']};
  const lookup = (records, messages = senders, uid = 'viewer') =>
    matchContactNumbers(firestore(records, messages), uid, ['existing']);
  assert.deepEqual(await lookup(data), {peer: phone});
  assert.deepEqual(await lookup(data, senders, 'stranger'), {});
  assert.deepEqual(await lookup(data, {[room]: ['viewer']}), {});
  assert.deepEqual(await lookup({...data, [consent]: {enabled: false}}), {});
  assert.deepEqual(await lookup({...data, [consent]: undefined}), {});
  assert.deepEqual(await lookup({...data, [peer]: {deleted: true}}), {});
  assert.deepEqual(await lookup({...data, [room]: {...data[room], isGroup: true}}), {});
  assert.deepEqual(await lookup({...data, [peer + '/blockedUsers/viewer']: {blocked: true}}), {});
  assert.deepEqual(await lookup({...data, ['users/viewer/blockedUsers/peer']: {blocked: true}}), {});
  assert.equal(await matchContactNumbers(firestore(data, senders), 'viewer', ['invalid/path']), null);
});
