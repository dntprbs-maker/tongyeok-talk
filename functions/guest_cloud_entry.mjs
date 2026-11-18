import {getFirestore} from 'firebase-admin/firestore';
import {defineSecret} from 'firebase-functions/params';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {processCloudGuestEvent} from './guest_cloud_translation.mjs';
import {PROJECT} from './rewards.mjs';

// Export from the Firebase entry point only when the isolated pilot is ready.
const guestTranslationKey = defineSecret('TONGYEOK_OPENAI_TRANSLATION_KEY');
export const guestCloudTranslation = onDocumentCreated({
  document: 'guestRooms/{roomId}/messages/{messageId}',
  region: 'asia-northeast3',
  serviceAccount: 'tongyeok-guest-worker@tongyeok-talk-lab-20261024.iam.gserviceaccount.com',
  secrets: [guestTranslationKey],
  retry: true,
  minInstances: 0,
  maxInstances: 1,
  concurrency: 2,
  memory: '256MiB',
  timeoutSeconds: 75,
}, async event => {
  if (process.env.GCLOUD_PROJECT !== PROJECT || event.data?.data()?.status !== 'cloud_pending') return;
  const result = await processCloudGuestEvent(getFirestore(), event.data, {apiKey: guestTranslationKey.value()});
  if (result) console.log(JSON.stringify({event: 'guest_cloud_translation', success: result.success}));
});
