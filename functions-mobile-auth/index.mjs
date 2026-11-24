import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {onRequest} from 'firebase-functions/v2/https';
import {exchangeMobileLogin} from './mobile-login.mjs';

initializeApp();

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
  const result = await exchangeMobileLogin({
    method: req.method,
    authorization: req.get('authorization'),
    purpose: req.body?.purpose,
    provider: req.body?.provider,
    verify: token => auth.verifyIdToken(token, true),
    issue: uid => auth.createCustomToken(uid),
  });
  res.status(result.status).json(result.body);
});
