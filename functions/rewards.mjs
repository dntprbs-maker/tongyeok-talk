import {createHash, randomBytes, verify} from 'node:crypto';

export const PROJECT = 'tongyeok-talk-lab-20261024';
export const REWARDS = Object.freeze({
  member: {unit:'6464698858', amount:100, item:'번역권', kind:'translations'},
  leader: {unit:'4167652668', amount:1, item:'하루권', kind:'day_pass'},
});
export const TEST_UNIT = '5224354917';
export const IOS_TEST_UNIT = '1712485313';
// These are this app's existing-account iOS units, not Android units.
export const IOS_AD_UNITS = Object.freeze({
  member:'ca-app-pub-7142914884555224/8993940063',
  leader:'ca-app-pub-7142914884555224/6918120261',
});
const memberCreditsPerAd = 50;
const leaderAdsPerDay = 2;
const DAY=86400000,KST=9*3600000;
export const midnightKst = at => Math.ceil((at+KST)/DAY)*DAY-KST;
export const passExpiry = (current, now) => {
  if (current > now) return midnightKst(current + DAY);
  return (Math.floor((now + KST) / DAY) + 1) * DAY - KST;
};
// The product is classified by selected language, never by a workplace role.
export function rewardRole(profile) {
  if (profile?.rewardQaRole === 'member') return 'member';
  if (profile?.preferredLanguage === 'Korean') return 'leader';
  if (profile?.preferredLanguage === 'Mongolian') return 'member';
  return undefined;
}
const hash = s => createHash('sha256').update(s).digest('hex');
// Dates are written by trusted server code, not supplied by clients. Keeping
// values SDK-neutral also permits the existing PC worker's Firestore adapter.
const stamp = () => new Date();
const fail = code => { throw new Error(code); };
const validUid = uid => typeof uid === 'string' && uid.length > 0 && uid.length <= 128 && !uid.includes('/');
const millis = value => value?.toMillis?.() ?? 0;

// Match Google's reference verifier (Java URI.getQuery): percent-decode the
// query once, preserving order and literal '+', then verify its UTF-8 bytes.
export async function verifyCallback(rawQuery, getKeys) {
  if (typeof rawQuery !== 'string' || rawQuery.length > 8192) fail('bad_callback');
  const match = /^(.*)&signature=([A-Za-z0-9_%=-]+)&key_id=(\d+)$/.exec(rawQuery);
  if (!match) fail('bad_signature_format');
  const params = new URLSearchParams(rawQuery);
  for (const key of new Set(params.keys())) if (params.getAll(key).length !== 1) fail('duplicate_parameter');
  const allowed = ['ad_network','ad_unit','custom_data','reward_amount','reward_item','timestamp','transaction_id','user_id','signature','key_id'];
  if ([...params.keys()].some(key => !allowed.includes(key))) fail('unknown_parameter');
  let pem = (await getKeys()).get(match[3]);
  if (!pem) pem = (await getKeys(true)).get(match[3]);
  if (!pem) fail('unknown_signing_key');
  const signature = Buffer.from(decodeURIComponent(match[2]), 'base64url');
  if (!verify('sha256', Buffer.from(decodeURIComponent(match[1]), 'utf8'), pem, signature)) fail('invalid_signature');
  const event = Object.fromEntries(params);
  if (!validUid(event.user_id) || !/^[a-f0-9]{64}$/.test(event.custom_data ?? '') ||
      !/^[A-Za-z0-9_-]{8,256}$/.test(event.transaction_id ?? '') ||
      !/^\d{13}$/.test(event.timestamp ?? '') || !/^\d+$/.test(event.reward_amount ?? '')) fail('bad_callback');
  return event;
}

// AdMob's URL verification tool deliberately uses these fixed dummy IDs.
// A valid Google signature is required by the caller. Acknowledge the check
// without minting rewards or consuming the real ad session/transaction.
export async function acknowledgeVerification(db,event,now=Date.now()) {
  if(event.ad_unit!=='1234567890'||event.transaction_id!=='123456789')return false;
  const ref=db.doc(`_adRewardSessions/${event.custom_data}`),check=db.doc(`_adRewardVerificationChecks/${event.custom_data}`);
  await db.runTransaction(async tx=>{
    const [s,c]=await tx.getAll(ref,check),value=s.data(),reward=REWARDS[value?.role];
    if(!s.exists||value.uid!==event.user_id||!reward||millis(value.expiresAt)<now||
      Number(event.reward_amount)!==(value.expectedRewardAmount??reward.amount)||
      event.reward_item!==(value.expectedRewardItem??reward.item))fail('reward_verification_mismatch');
    if(!c.exists)tx.create(check,{uid:value.uid,kind:reward.kind,source:'admob_verification_tool',signatureVerified:true,verifiedAt:new Date(now)});
  });
  return true;
}

export function googleKeys(fetcher = fetch) {
  let cached, expires = 0, fetchedAt = 0, inFlight;
  return async (refresh=false) => {
    if (cached && Date.now() < expires && (!refresh || Date.now()-fetchedAt<30000)) return cached;
    if (!inFlight) inFlight = (async () => {
      const response = await fetcher('https://www.gstatic.com/admob/reward/verifier-keys.json', {signal:AbortSignal.timeout(10000)});
      if (!response.ok) fail('key_server_unavailable');
      const data = await response.json();
      if (!Array.isArray(data.keys) || !data.keys.length) fail('key_server_unavailable');
      cached = new Map(data.keys.map(k => [String(k.keyId), k.pem]));
      fetchedAt = Date.now();
      expires = Date.now() + 3600000;
      return cached;
    })().finally(() => { inFlight = undefined; });
    return inFlight;
  };
}

export async function createSession(db, {uid, testAds = false, platform='android'}, {enabled=false, localTest=false, now=Date.now(), iosUnits={}} = {}) {
  if (!enabled) fail('rewards_not_ready');
  if (!validUid(uid) || typeof testAds !== 'boolean' || !['android','ios'].includes(platform)) fail('invalid_request');
  if (testAds && !localTest) fail('test_rewards_disabled');
  const id = randomBytes(32).toString('hex');
  const session = db.doc(`_adRewardSessions/${id}`), user = db.doc(`users/${uid}`);
  const throttle = db.doc(`_adRewardLimits/${uid}`);
  return db.runTransaction(async tx => {
    const [u, limit] = await tx.getAll(user, throttle);
    const role = rewardRole(u.data());
    // Rollout is restricted to operator-assigned developer test accounts.
    if (!u.exists || u.data().rewardAdEnabled !== true || !REWARDS[role]) fail('reward_account_not_enabled');
    const last = limit.data();
    if (last && now - millis(last.lastSessionAt) < 30000) fail('reward_rate_limited');
    const day = new Date(now).toISOString().slice(0,10);
    const count = last?.day === day ? last.count ?? 0 : 0;
    if (count >= 20) fail('reward_daily_limit');
    const reward = REWARDS[role];
    const configured=platform==='ios'?iosUnits[role]:`ca-app-pub-7142914884555224/${reward.unit}`;
    if(!testAds && (typeof configured!=='string'||!/^ca-app-pub-7142914884555224\/\d{10}$/.test(configured)))fail('ios_ads_not_configured');
    const adUnitId=testAds?`ca-app-pub-3940256099942544/${platform==='ios'?IOS_TEST_UNIT:TEST_UNIT}`:configured;
    // AdMob metadata is pinned when the server creates the session. Existing
    // Android metadata remains 100; the actual member entitlement remains 50.
    const expectedRewardAmount=platform==='ios'&&role==='member'?memberCreditsPerAd:reward.amount;
    tx.create(session, {uid, role, kind:reward.kind, platform, expectedUnit:adUnitId.split('/')[1],
      expectedRewardAmount,expectedRewardItem:reward.item,testAds, status:'pending', createdAt:new Date(now), expiresAt:new Date(now+30*60000)});
    tx.create(db.doc(`users/${uid}/adRewardReceipts/${id}`),{status:'pending',kind:reward.kind,testAds,createdAt:new Date(now),expiresAt:new Date(now+30*60000)});
    tx.set(throttle, {day, count:count+1, lastSessionAt:new Date(now)});
    return {sessionId:id, platform, kind:reward.kind, amount:expectedRewardAmount,adUnitId};
  });
}

export async function grantReward(db, event, {localTest=false, now=Date.now()} = {}) {
  const session = db.doc(`_adRewardSessions/${event.custom_data}`);
  const transaction = db.doc(`_adRewardTransactions/${hash(event.transaction_id)}`);
  return db.runTransaction(async tx => {
    const [s, existing] = await tx.getAll(session, transaction);
    if (!s.exists) fail('unknown_session');
    const data = s.data(), reward = REWARDS[data.role];
    if (localTest && !data.testAds) fail('test_rewards_disabled');
    if (!reward || event.user_id !== data.uid) fail('reward_owner_mismatch');
    if (existing.exists) {
      if (existing.data().sessionId !== session.id || existing.data().uid !== data.uid) fail('transaction_reused');
      return {duplicate:true};
    }
    if (data.status !== 'pending') fail('session_already_used');
    const eventAt = Number(event.timestamp);
    if (!Number.isSafeInteger(eventAt) || eventAt < millis(data.createdAt)-60000 ||
        eventAt > millis(data.expiresAt) || eventAt > now+60000 || now-eventAt > 86400000) fail('reward_expired');
    if (data.testAds) {
      if (!localTest || event.ad_unit !== (data.expectedUnit??TEST_UNIT) || Number(event.reward_amount) < 1) fail('test_rewards_disabled');
    } else if (event.ad_unit !== (data.expectedUnit??reward.unit) ||
        Number(event.reward_amount) !== (data.expectedRewardAmount??reward.amount) ||
        event.reward_item !== (data.expectedRewardItem??reward.item)) fail('reward_mismatch');
    const wallet = db.doc(`translationWallets/${data.uid}`), user = db.doc(`users/${data.uid}`);
    const [w, u] = await tx.getAll(wallet,user);
    if (u.data()?.rewardAdEnabled !== true || rewardRole(u.data()) !== data.role) fail('reward_account_not_enabled');
    const value = w.data() ?? {};
    const patch = {updatedAt:stamp()};
    let amount = memberCreditsPerAd;
    if (data.role === 'member') {
      patch.balance = (value.balance ?? 0) + amount;
    } else {
      const progress = value.leaderRewardAdProgress === 1 ? 1 : 0;
      const completed = progress + 1;
      amount = completed === leaderAdsPerDay ? 1 : 0;
      patch.leaderRewardAdProgress = completed % leaderAdsPerDay;
      if (amount) {
        patch.leaderPassUntil = new Date(passExpiry(millis(value.leaderPassUntil),now));
      }
    }
    tx.set(wallet,patch,{merge:true});
    tx.create(wallet.collection('entries').doc(`ad_${hash(event.transaction_id)}`), {
      type:'ad_reward', source:data.testAds?'admob_test':'admob_ssv', kind:reward.kind,
      amount, sessionId:session.id, transactionId:event.transaction_id,
      createdAt:stamp(),
    });
    tx.create(transaction,{uid:data.uid,sessionId:session.id,createdAt:stamp()});
    tx.update(session,{status:'granted',grantedAt:stamp()});
    // Owner-readable receipt contains no private callback payload.
    tx.set(db.doc(`users/${data.uid}/adRewardReceipts/${session.id}`),{status:'granted',kind:reward.kind,amount,testAds:data.testAds,createdAt:stamp()});
    return {duplicate:false,kind:reward.kind,amount};
  });
}
