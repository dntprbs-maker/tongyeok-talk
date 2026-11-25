import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {onRequest} from 'firebase-functions/v2/https';
import {exchangeMobileLogin} from './mobile-login.mjs';
import {qaAccess} from './qa-access.mjs';

initializeApp();

const reviewUids = new Set(
  (process.env.TONGYEOK_REVIEW_UIDS ?? '').split(',').map(uid => uid.trim()).filter(Boolean),
);

export const mobileAuthExchange = onRequest({
  region: 'asia-northeast3',
  cors: false,
  maxInstances: 2,
  timeoutSeconds: 15,
  serviceAccount: 'tongyeok-mobile-auth@tongyeok-talk-lab-20261024.iam.gserviceaccount.com',
}, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  if (process.env.GCLOUD_PROJECT !== 'tongyeok-talk-lab-20261024') {
    res.sendStatus(503);
    return;
  }
  const auth = getAuth();
  const purpose = req.body?.purpose;
  if (purpose === 'qa-access' || purpose === 'qa-switch') {
    const result = await qaAccess({
      method: req.method,
      authorization: req.get('authorization'),
      purpose,
      target: req.body?.target,
      config: {
        operator: process.env.TONGYEOK_QA_OPERATOR_UID,
        korean: process.env.TONGYEOK_QA_KOREAN_UID,
        mongolian: process.env.TONGYEOK_QA_MONGOLIAN_UID,
      },
      verify: token => auth.verifyIdToken(token, true),
      issue: (uid, claims) => auth.createCustomToken(uid, claims),
    });
    res.status(result.status).json(result.body);
    return;
  }
  const result = await exchangeMobileLogin({
    method: req.method,
    authorization: req.get('authorization'),
    purpose,
    provider: req.body?.provider,
    reviewUids,
    verify: token => auth.verifyIdToken(token, true),
    issue: uid => auth.createCustomToken(uid),
  });
  res.status(result.status).json(result.body);
});
