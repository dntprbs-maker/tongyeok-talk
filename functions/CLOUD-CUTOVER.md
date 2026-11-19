# PC worker to Firebase cutover

This is the existing isolated `tongyeok-talk-lab-20261024` project. No public
release and no new project. Existing reward/referral functions are unchanged.

## Safety and preparation

- Keep the PC worker source, logs, budgets, and QA data. No history deletion.
- Create `_workerControl/cloud` with `enabled:false` before deploying the five
  new functions. They fail closed if this document is absent or disabled.
- Secrets: existing OpenAI key and VAPID JSON go only into Secret Manager;
  never into source/environment files in this repository. Await explicit
  credential-transfer approval. Grant only this project's existing server
  account read access to these two secrets and FCM send permission.
- Deploy only `memberTranslation`, `memberTranslationRetry`,
  `memberCreditRequest`, `guestTranslation`, and `messagePush`.
- Confirm all five functions ACTIVE; do not stop a healthy PC worker first.
- Existing allowance is cumulative 200 attempts / USD0.25. Seed
  `_workerBudgets/memberCloudTrial` from the PC's final ledger once, without
  resetting it or overwriting an existing cloud ledger. This is still the
  approved trial allowance, not unlimited production capacity.

## Switch and actual verification

1. Verify exact PID/command lines, allow in-flight translations to settle,
   stop only the two named tongyeok PC workers, and verify they exited.
2. Migrate the final budget and set cloud `enabled:true` with a server timestamp.
   `pushTestUids` retains only the existing QA iOS/Web/Note10 audience.
3. Inspect messages created during the cutover gap. Explicitly recover only
   unfinished gap messages, with the same event receipts and reservations.
   Do not replay previously completed messages or send historical alerts.
4. Send new messages through the real web/iPhone/Note10 interfaces. Confirm
   dictionary-only API0, mixed/all-new API1, one bubble, one debit, failed
   translation refund, and physical iPhone background push.
5. Verify Cloud Logging and `_pushDispatch`/event receipts, while confirming
   PC worker PIDs remain absent. A deploy success alone is not completion.

## Rollback

Disable `_workerControl/cloud` first and wait for in-flight work to settle.
Use actual receipt/credit state to avoid replaying uncertain work. Restore the
PC workers from their existing private launch configuration only if necessary;
never run both paths concurrently. Merge the cloud's cumulative allowance back
without resetting prior consumption. No secret deletion or role revocation is
part of this rollback without checking dependencies.

## Checks

Run a fresh dedicated Firestore emulator on 127.0.0.1:8766, then:

`FIRESTORE_EMULATOR_HOST=127.0.0.1:8766 node --test functions/test/*.test.mjs`

The emulator rules fixture is the preserved current PC worker's rules snapshot;
it is not a command to replace deployed security rules.

## Verified cutover — 2026-11-19 KST

- Explicit credential transfer and FCM send permission approvals received.
- Both existing secrets stored in this project's Secret Manager; accessor granted
  only on those secrets to the existing server account.
- Custom project role `tongyeokNotificationSender` contains only
  `cloudmessaging.messages.create`. Broad FCM admin role was not granted.
- Eventarc account has `roles/run.invoker` on the five new services individually;
  no public invocation binding was added.
- All five new functions ACTIVE. Existing reward/referral update times unchanged.
- PC worker PIDs 5772/38476 stopped; final ledger 71 calls / USD0.003672418
  migrated once. Cloud enabled at 2026-11-19T13:42:25Z; no cutover-gap messages.
- Actual cloud tests: Korean/Mongolian paid translations, existing dictionary
  API0, mixed sentences API1, retry without duplicate debit, guest translation.
  Wallet reserved count returned to zero. Trial allowance remains 200 / USD0.25.
- Found and fixed HTTP-v1 vs Admin SDK Android payload incompatibility (TTL and
  channel ID). Added actual Admin SDK validation to duplicate push regression.
  23 emulator tests passed. Failed QA dispatch records retained.
- New iPhone lock-screen notification and Note10 background notification directly
  observed over existing USB/ADB connections while both PC workers remained off.
- QA audience is retained. This is a development cutover, not App Store release,
  unlimited usage approval, or a claim that every release flow has passed.
