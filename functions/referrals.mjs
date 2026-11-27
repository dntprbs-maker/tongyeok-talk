import {randomBytes} from 'node:crypto';
import {midnightKst, rewardRole} from './rewards.mjs';

const dayMs = 86400000;
const kst = 9 * 3600000;
const roleOf = profile => profile?.deleted ? undefined : rewardRole(profile);
const timestamp = value => value?.toMillis?.() ?? 0;
const contactFor = (db, uid) => db.doc(`users/${uid}/private/contact`);
const referralFor = (db, uid) => db.doc(`_referrals/${uid}`);
const newReferralWaitDays = 0;

export async function referralStatus(db, uid) {
  const profile = (await db.doc(`users/${uid}`).get()).data();
  if (!roleOf(profile) || !(await contactFor(db, uid).get()).exists) {
    throw Error('referral_unavailable');
  }
  const codeRef = db.doc(`_referralOwnerCodes/${uid}`);
  const code = await db.runTransaction(async tx => {
    const existing = (await tx.get(codeRef)).data();
    if (existing) return existing.code;
    const nextCode = randomBytes(8).toString('hex').toUpperCase();
    tx.create(db.doc(`_referralCodes/${nextCode}`), {uid});
    tx.create(codeRef, {code:nextCode});
    return nextCode;
  });
  const rows = await db.collection('_referrals').where('inviter', '==', uid).get();
  return {
    code,
    waitDays: newReferralWaitDays,
    pending: rows.docs.filter(doc => !doc.data().grantedAt).length,
    rewarded: rows.docs.filter(doc => doc.data().grantedAt).length,
  };
}

export async function registerReferral(db, uid, input) {
  const code = typeof input === 'string' ? input.trim().toUpperCase() : '';
  if (!/^[A-F0-9]{16}$/.test(code)) throw Error('invalid_referral_code');
  const ref = referralFor(db, uid);
  return db.runTransaction(async tx => {
    const [existing, codeDoc, contact, invitee] = await tx.getAll(
      ref, db.doc(`_referralCodes/${code}`), contactFor(db, uid), db.doc(`users/${uid}`),
    );
    const inviter = codeDoc.data()?.uid;
    if (!inviter || inviter === uid) throw Error('invalid_referral_code');
    if (existing.data()?.inviter === inviter) return {registered:true};
    if (contact.exists || existing.exists) throw Error('referral_already_registered');
    const [inviterProfile, inviterContact] = await tx.getAll(
      db.doc(`users/${inviter}`), contactFor(db, inviter),
    );
    const inviterRole = roleOf(inviterProfile.data());
    const inviteeRole = roleOf(invitee.data());
    if (!inviterContact.exists || !inviterRole || !inviteeRole || inviterRole === inviteeRole) {
      throw Error('referral_role_mismatch');
    }
    tx.create(ref, {inviter, inviterRole, inviteeRole, activityDays:[], waitDays:newReferralWaitDays});
    return {registered:true};
  });
}

export async function recordReferralActivity(db, uid, at) {
  const ref = referralFor(db, uid);
  await db.runTransaction(async tx => {
    const referral = (await tx.get(ref)).data();
    if (!referral || referral.grantedAt || referral.activityDays.length >= 10) return;
    const contact = await tx.get(contactFor(db, uid));
    const joined = timestamp(contact.createTime);
    if (!joined || at < joined) return;
    const day = Math.floor((at + kst) / dayMs);
    if (referral.activityDays.includes(day)) return;
    const activityDays = [...referral.activityDays, day];
    const patch = {activityDays};
    if (activityDays.length === 10) patch.nextCheckAt = new Date(at);
    tx.update(ref, patch);
  });
}

const roles = ['leader', 'member'];

export async function grantReferral(db, ref, now = Date.now()) {
  return db.runTransaction(async tx => {
    const referral = (await tx.get(ref)).data();
    if (!referral || referral.grantedAt || referral.cancelledAt ||
        referral.activityDays.length < 10 ||
        !timestamp(referral.nextCheckAt) || timestamp(referral.nextCheckAt) > now) return false;
    const inviterUid = referral.inviter;
    const inviteeUid = ref.id;
    const inviterRole = referral.inviterRole;
    const inviteeRole = referral.inviteeRole;
    if (typeof inviterUid !== 'string' || !inviterUid || inviterUid.includes('/') ||
        inviterUid === inviteeUid || !roles.includes(inviterRole) ||
        !roles.includes(inviteeRole) || inviterRole === inviteeRole) {
      tx.update(ref, {nextCheckAt:null, cancelledAt:new Date(now)});
      return false;
    }
    const inviterWallet = db.doc(`translationWallets/${inviterUid}`);
    const inviteeWallet = db.doc(`translationWallets/${inviteeUid}`);
    const receiptFor = wallet => wallet.collection('entries').doc(`referral_${inviteeUid}`);
    const [inviterBalance, inviteeBalance, inviter, invitee, inviterContact,
      inviteeContact, inviterReceipt, inviteeReceipt] = await tx.getAll(
      inviterWallet, inviteeWallet, db.doc(`users/${inviterUid}`), db.doc(`users/${inviteeUid}`),
      contactFor(db, inviterUid), contactFor(db, inviteeUid),
      receiptFor(inviterWallet), receiptFor(inviteeWallet),
    );
    if (!inviterContact.exists ||
        !inviteeContact.exists || !roleOf(inviter.data()) || !roleOf(invitee.data())) {
      tx.update(ref, {nextCheckAt:null, cancelledAt:new Date(now)});
      return false;
    }
    const pay = (wallet, balance, role, beneficiary, paid) => {
      if (paid) return false;
      const leader = role === 'leader';
      const amount = leader ? 5 : 500;
      const value = balance.data() ?? {};
      const reward = leader
        ? {leaderPassUntil:new Date(midnightKst(Math.max(now, timestamp(value.leaderPassUntil)) + amount * dayMs))}
        : {balance:(value.balance ?? 0) + amount};
      tx.set(wallet, {...reward, updatedAt:new Date(now)}, {merge:true});
      tx.create(receiptFor(wallet), {
        type:'referral_reward', kind:leader ? 'day_pass' : 'translations', amount, beneficiary,
        createdAt:new Date(now),
      });
      return true;
    };
    const paidInviter = pay(inviterWallet, inviterBalance, inviterRole, 'inviter', inviterReceipt.exists);
    const paidInvitee = pay(inviteeWallet, inviteeBalance, inviteeRole, 'invitee', inviteeReceipt.exists);
    tx.update(ref, {grantedAt:new Date(now), nextCheckAt:null});
    return paidInviter || paidInvitee;
  });
}