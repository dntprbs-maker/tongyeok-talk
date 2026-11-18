import {FieldValue} from 'firebase-admin/firestore';
import {openaiTranslationModel, translateWithOpenAI} from './openai_translation.mjs';
import {processGuestTranslation} from './guest_chat.mjs';

const pilotCallLimit = 12;

export function processCloudGuestEvent(db, snapshot, {apiKey, call = translateWithOpenAI} = {}) {
  if (snapshot?.data()?.status !== 'cloud_pending') return false;

  return processGuestTranslation(db, snapshot.ref, async input => {
    if (!apiKey) throw Error('cloud_translation_key_missing');

    const budget = db.doc('_workerBudgets/guestCloudTrial');
    await db.runTransaction(async tx => {
      const used = (await tx.get(budget)).data()?.calls ?? 0;
      if (!Number.isSafeInteger(used) || used < 0 || used >= pilotCallLimit) {
        throw Error('cloud_translation_budget_limit');
      }
      tx.set(budget, {calls: used + 1, updatedAt: FieldValue.serverTimestamp()});
    });

    const result = await call({model: openaiTranslationModel, ...input}, {apiKey});
    if (result.actualModel !== openaiTranslationModel) throw Error('unexpected_response_model');
    return result;
  }, {cloudTrial: true});
}
