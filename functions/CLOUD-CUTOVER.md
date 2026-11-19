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
