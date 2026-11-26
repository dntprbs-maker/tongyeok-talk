export async function matchContactNumbers(db, uid, roomIds) {
  if (!Array.isArray(roomIds) || roomIds.length < 1 || roomIds.length > 30 ||
      roomIds.some(id => typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,120}$/.test(id))) {
    return null;
  }
  const rooms = await db.getAll(...[...new Set(roomIds)].map(id => db.doc('conversations/' + id)));
  const peers = new Map();
  for (const room of rooms) {
    const data = room.data();
    const members = data?.participants;
    if (data?.isGroup === true || !Array.isArray(members) || members.length !== 2 ||
        !members.includes(uid)) continue;
    const peer = members.find(member => member !== uid);
    if (typeof peer === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(peer)) {
      if (!peers.has(peer)) peers.set(peer, []);
      peers.get(peer).push(room.ref);
    }
  }
  if (!peers.size) return {};
  const references = [...peers.keys()].flatMap(peer => [
    db.doc('users/' + peer),
    db.doc('users/' + peer + '/private/contactMatchConsent'),
    db.doc('users/' + peer + '/private/contact'),
    db.doc('users/' + peer + '/blockedUsers/' + uid),
    db.doc('users/' + uid + '/blockedUsers/' + peer),
  ]);
  const records = await db.getAll(...references);
  const checks = [];
  let offset = 0;
  for (const [peer, rooms] of peers) {
    const [profile, consent, contact, peerBlock, viewerBlock] = records.slice(offset, offset + 5);
    offset += 5;
    const phone = contact.data()?.phoneE164;
    if (profile.exists && profile.data()?.deleted !== true && consent.data()?.enabled === true &&
        peerBlock.data()?.blocked !== true && viewerBlock.data()?.blocked !== true &&
        typeof phone === 'string' && /^\+(82|976)[0-9]{7,11}$/.test(phone)) {
      checks.push((async () => {
        // A room can be created by a single participant. Confirm the peer actually joined it.
        const sent = await Promise.all(rooms.map(room => room.collection('messages')
          .where('senderId', '==', peer).limit(1).get()));
        return sent.some(messages => !messages.empty) ? [peer, phone] : null;
      })());
    }
  }
  return Object.fromEntries((await Promise.all(checks)).filter(entry => entry !== null));
}
