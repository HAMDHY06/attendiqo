# Phase 7 Functions production review

Status: review-only. Nothing in this document authorizes deployment.

## Package and runtime boundary

`Firebase/functions` is the complete deployment source. Its canonical modules
are:

- `lib/parent_projection_validation.mjs` for sanitization, stable IDs, version
  checks, institute/link validation, and safe audit payloads.
- `lib/parent_projection_writers.mjs` for link lifecycle, access-scope
  recomputation, projection synchronization, and institute-migration
  invalidation.

`scripts/lib/parent_projection_validation.mjs` re-exports validation. The writer
wrapper delegates every operation to the packaged canonical writer while
injecting the scripts package's own Admin SDK `FieldValue`; it contains no
projection business logic. The package test rejects relative imports outside
the Functions root, copies the exact entry point and `lib` tree into a staging
directory, loads `index.mjs`, and checks all eight callables.

Production is pinned to Node 22 in `package.json` and checked at module load.
Local emulator execution may explicitly fall back to Node 24. The used ESM,
Web Fetch, crypto, and Firebase APIs are supported by Node 22; the fallback does
not certify Node 24 for production. CI must run package, unit, and integration
tests on Node 22 before approval. Do not silently change the runtime.

## Callable trust boundary

Each request passes callable authentication, explicit Admin SDK ID-token
verification and UID equality, App Check, hashed actor/operation rate limiting,
source-derived institute lookup, active same-institute Institute Admin checks,
and an idempotency claim before a canonical writer runs. Errors expose only a
stable callable code and safe message. Allowed and denied operations store only
the operation, outcome, safe code, actor hash, verified institute ID, and
server timestamp.

## Android App Check staging

1. Select the approved Android provider in Firebase staging. Use Play Integrity
   for release validation; use the App Check debug provider only on controlled
   development builds.
2. Enable the debug provider locally, capture its one-time debug token from the
   device log, and register that token in the staging Firebase console. Never
   commit or paste it into source, documentation, CI logs, or screenshots.
3. With enforcement enabled in staging, call a harmless reviewed operation
   without App Check. Expect `failed-precondition` and "App verification is
   required", with no backend writer activity.
4. Repeat from the registered debug build. Authentication, role, institute,
   and source validation must still apply; App Check alone grants nothing.
5. Build the signed release candidate with Play Integrity, confirm a valid App
   Check token reaches the callable, then repeat missing/invalid-token negative
   tests. Record only pass/fail and safe error codes.

The emulator verifies the missing-token contract but cannot replace staging
provider and release-token validation.

## Rate limits, idempotency, and TTL readiness

The review default is 20 requests per actor hash, operation, and minute.
`backend_rate_limits.expiresAt` is two windows after the bucket start.
`backend_idempotency.expiresAt` is 24 hours after the claim. These are cleanup
timestamps, not authorization controls.

After staging load tests, review per-operation limits separately: link changes
should be lower than reconciliation operations. Alert on sustained throttling.
If production is approved, configure Firestore TTL on `expiresAt` for both
collections through a separately reviewed infrastructure change. TTL deletion
is asynchronous, must not be assumed immediate, and must not replace Rules or
explicit status checks. No TTL policy was enabled in this task.

## Recommended deployment settings (not configured)

- Region: colocate with the approved Firestore region and data-residency plan;
  validate the closest supported Asia region for Sri Lankan users before
  selecting it.
- Instances/concurrency: start with min instances 0 and a conservative
  concurrency of 20, then tune from staging transaction-contention and latency
  measurements.
- Memory/timeout: retain the reviewed 256 MiB and 60 seconds initially; lower
  timeout per lightweight operation after profiling rather than increasing it
  globally.
- Monitoring: alert on 5xx/internal errors, latency, transaction aborts,
  App Check failures, authorization denials, rate-limit exhaustion, and unusual
  invocation volume. Logs must not include request payloads or personal data.
- Retention: propose 365 days for safe callable/domain audit records subject to
  legal review; retain idempotency documents 24 hours and rate buckets only
  until TTL cleanup. Audit retention must be a separately approved policy.

## Dependency review

Direct dependencies are current: `firebase-admin@14.2.0` and
`firebase-functions@7.3.2`. The audit reports seven moderate findings rooted at
`uuid@9.0.1` through the Admin SDK storage dependency chain (`gaxios@6.7.1`,
`retry-request@7.0.2`, `teeny-request@9.0.0`, and
`@google-cloud/storage@7.21.0`). `npm outdated` reports no direct update. npm's
only complete suggested remediation is a forced downgrade to
`firebase-admin@10.3.0`, which is breaking and was rejected. Track upstream;
do not use `npm audit fix --force`.

## Local validation

```powershell
npm.cmd --prefix Firebase\functions test
npm.cmd --prefix Firebase\functions run test:integration
npm.cmd --prefix Firebase\functions run test:package

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

firebase.cmd emulators:exec --only auth,firestore,functions `
  --project attendiqo-system --config Firebase\firebase.json `
  "npm.cmd --prefix Firebase\functions run test:emulator-smoke"
```

Before any future deployment, also run the full Flutter, backend, Rules,
package, audit, secret-scan, and diff checks documented in Phase 7.
