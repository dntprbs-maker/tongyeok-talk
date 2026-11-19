import {randomUUID} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {dictionaryKey} from './translation_dictionary.mjs';

const policyStart = Date.parse('2026-11-16T07:16:00Z');
// Keep the original precision for existing fractional balances and reservations.
const unitsPerCredit = 2520;
const leaseMs = 5 * 60 * 1000;
const units = value => Math.round((value ?? 0) * unitsPerCredit);

export function groupDictionaryKey(source, target, text) {
  return dictionaryKey({source, target, text});
}

export function usesGroupSplit(room) {
  return room.data()?.isGroup === true &&
    room.createTime?.toMillis() >= policyStart;
}

export async function processGroupTranslation(db, ref, room, provider, {providerChecksDictionary = false} = {}) {
  const token = randomUUID();
  const startedAt = Date.now();
  const claimRef = ref.collection('_groupBilling').doc('translation');
  const job = await db.runTransaction(async tx => {
    const [message, claim, roomDoc] = await tx.getAll(ref, claimRef, room.ref);
    const data = message.data();
    if (!data || data.translationStatus === 'done' || !usesGroupSplit(roomDoc)) return null;
    const existing = claim.data();
    if (existing?.status === 'reserved' && existing.leaseUntil > startedAt) return null;
    if (existing?.status === 'done' || (existing?.attempts ?? 0) >= 3 && existing?.status !== 'reserved') return null;

    const participants = [...new Set(roomDoc.data().participants ?? [])];
    if (!participants.includes(data.senderId) || participants.length < 2 || participants.length > 11) return null;
    const profiles = await tx.getAll(...participants.map(uid => db.doc(`users/${uid}`)));
    const languages = new Map(profiles.map(doc => [doc.id, doc.data()?.preferredLanguage]));
    const recovering = existing?.status === 'reserved';
    const source = recovering ? existing.source :
      (languages.get(data.senderId) === 'Mongolian' ? 'mn' : 'ko');
    const target = source === 'ko' ? 'mn' : 'ko';
    const privateDelivery = recovering ? existing.privateDelivery === true : source === 'ko';
    const view = uid => ref.collection('creditTranslations').doc(uid);
    let charges = recovering ? existing.charges : null;
    if (!charges) {
      const receivers = participants.filter(uid => uid !== data.senderId &&
        languages.get(uid) === (target === 'mn' ? 'Mongolian' : 'Korean'));
      if (!receivers.length) {
        tx.update(ref, {translations: {[source]: data.originalText}, translationStatus: 'done'});
        return null;
      }
      const payers = source === 'mn' ? [data.senderId] : receivers;
      const lane = 'balance';
      const reserved = 'reserved';
      charges = payers.map(uid => ({uid, lane, reserved, share: unitsPerCredit}));
      const wallets = await tx.getAll(...payers.map(uid => db.doc(`translationWallets/${uid}`)));
      const funded = new Set(wallets.filter(wallet => {
        const value = wallet.data();
        return units(value?.balance) - units(value?.reserved) >= unitsPerCredit;
      }).map(wallet => wallet.id));
      if (!privateDelivery && !funded.has(data.senderId)) {
        tx.update(ref, {translationStatus: 'failed', translationError: 'group_no_credit'});
        return null;
      }
      if (privateDelivery) {
        for (const uid of receivers) {
          tx.set(view(uid), {status: funded.has(uid) ? 'pending' : 'original_only'});
        }
      }
      charges = charges.filter(charge => funded.has(charge.uid));
      if (!charges.length) {
        tx.update(ref, {
          creditManaged: true, translations: {[source]: data.originalText},
          translationStatus: 'done', translationError: FieldValue.delete(),
        });
        tx.set(claimRef, {status: 'done', charges: [], privateDelivery});
        return null;
      }
      const walletsById = new Map(wallets.map(wallet => [wallet.id, wallet]));
      for (const charge of charges) {
        const wallet = walletsById.get(charge.uid);
        tx.update(wallet.ref, {
          [charge.reserved]: (units(wallet.data()[charge.reserved]) + charge.share) / unitsPerCredit,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    tx.set(claimRef, {
      token, charges, source, target, privateDelivery, leaseUntil: startedAt + leaseMs,
      attempts: (existing?.attempts ?? 0) + 1, status: 'reserved',
    });
    tx.update(ref, {
      ...(privateDelivery ? {creditManaged: true} : {}),
      translationStatus: 'pending', translationError: FieldValue.delete(),
    });
    return {source, target, text: data.originalText};
  });
  if (!job) return;

  let result;
  try {
    const entry = providerChecksDictionary ? undefined :
      (await db.doc(`_groupTranslationDictionary/${groupDictionaryKey(job.source, job.target, job.text)}`).get()).data();
    result = entry?.approved === true && typeof entry.translation === 'string' && entry.translation.trim()
      ? {translation: entry.translation.trim(), actualModel: 'dictionary'}
      : await provider(job);
    if (!result?.translation?.trim()) throw new Error('group_empty_translation');
  } catch {
    result = null;
  }

  await db.runTransaction(async tx => {
    const claim = (await tx.get(claimRef)).data();
    if (claim?.status !== 'reserved' || claim.token !== token) return;
    const wallets = await tx.getAll(...claim.charges.map(({uid}) => db.doc(`translationWallets/${uid}`)));
    claim.charges.forEach((charge, i) => {
      const {lane, reserved, share} = charge;
      const wallet = wallets[i];
      const balance = units(wallet.data()?.[lane]);
      const held = units(wallet.data()?.[reserved]);
      if (held < share || balance < share) throw new Error('group_wallet_invariant');
      tx.update(wallet.ref, {
        [lane]: (balance - (result ? share : 0)) / unitsPerCredit,
        [reserved]: (held - share) / unitsPerCredit,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (result) tx.set(wallet.ref.collection('entries').doc(`group-${ref.parent.parent.id}-${ref.id}`), {
        type: 'group_translation', amount: -share / unitsPerCredit, lane,
        room: ref.parent.parent.id, message: ref.id,
        createdAt: FieldValue.serverTimestamp(),
      });
      if (claim.privateDelivery) {
        tx.set(ref.collection('creditTranslations').doc(charge.uid),
          result ? {status: 'done', translation: result.translation} : {status: 'failed'});
      }
    });
    tx.update(claimRef, {status: result ? 'done' : 'failed', finishedAt: FieldValue.serverTimestamp()});
    tx.update(ref, result ? {
      sourceLang: job.source,
      translations: claim.privateDelivery
        ? {[job.source]: job.text}
        : {[job.source]: job.text, [job.target]: result.translation},
      translationStatus: 'done', translationError: FieldValue.delete(),
      translationModel: result.actualModel ?? '',
      translatedAt: FieldValue.serverTimestamp(),
    } : {translationStatus: 'failed', translationError: 'group_translation_failed'});
  });
}
