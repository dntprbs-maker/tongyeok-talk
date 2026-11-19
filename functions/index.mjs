import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {defineBoolean} from 'firebase-functions/params';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {grantReferral, recordReferralActivity} from './referrals.mjs';
import {rewardHandler} from './http.mjs';
import {PROJECT,IOS_AD_UNITS} from './rewards.mjs';

initializeApp();
const referralRuntime = {
  region:'asia-northeast3',
  serviceAccount:'tongyeok-ad-rewards@tongyeok-talk-lab-20261024.iam.gserviceaccount.com',
};
export const referralActivity = onDocumentCreated({
  ...referralRuntime, document:'conversations/{room}/messages/{message}',
}, async event => {
  if (process.env.GCLOUD_PROJECT !== PROJECT || !event.data) return;
  const message=event.data.data();
  if (typeof message?.senderId === 'string' && message.originalText?.trim()) {
    await recordReferralActivity(getFirestore(),message.senderId,event.data.createTime.toMillis());
  }
});
export const referralPayout = onSchedule({
  ...referralRuntime, schedule:'every 60 minutes', timeZone:'Asia/Seoul', retryCount:3,
}, async () => {
  if (process.env.GCLOUD_PROJECT !== PROJECT) return;
  const db=getFirestore(), now=Date.now();
  const due=await db.collection('_referrals').where('nextCheckAt','<=',new Date(now)).limit(100).get();
  for (const referral of due.docs) await grantReferral(db,referral.ref,now);
});
const enabled=defineBoolean('AD_REWARDS_ENABLED',{default:false});
const iosRewardsEnabled=defineBoolean('IOS_AD_REWARDS_ENABLED',{default:false});
export const rewardApi=onRequest({region:'asia-northeast3',minInstances:0,maxInstances:2,
  concurrency:20,memory:'256MiB',timeoutSeconds:30,cors:false,
  serviceAccount:'tongyeok-ad-rewards@tongyeok-talk-lab-20261024.iam.gserviceaccount.com'}, async (req,res)=>{
  if (process.env.GCLOUD_PROJECT !== PROJECT) {res.status(503).send('project_guard');return;}
  // Express retains originalUrl; signed query bytes must never be reconstructed.
  req.url=req.originalUrl;
  await rewardHandler({
    db:getFirestore(),authenticate:token=>getAuth().verifyIdToken(token),enabled:enabled.value(),
    iosUnits:iosRewardsEnabled.value()?IOS_AD_UNITS:{},
  })(req,res);
});


export {memberTranslation,memberTranslationRetry,memberCreditRequest,guestTranslation,messagePush,userRewardEnrollment} from './cloud_entry.mjs';
