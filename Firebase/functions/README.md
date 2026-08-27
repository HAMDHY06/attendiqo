# Trusted backend placeholder

No Cloud Functions are deployed by this foundation. A later backend should validate attendance events, send FCM, optionally send SMS, enforce idempotency, store delivery results, and read secrets from Firebase/Google Cloud Secret Manager. Never import provider credentials into Flutter code.

## Phase 3 privileged account boundary

Institute Admin creation, disabling, and temporary-password reset are privileged operations. A future callable function must verify the Firebase ID token has `superAdmin: true`, confirm the caller's `users/{uid}` profile is active and has role `superAdmin`, validate the institute and request, use the Admin SDK for Authentication/custom claims/profile writes, and append a non-sensitive audit entry. It must never log or persist a temporary password.

The Flutter layer depends on `InstituteAdminProvisioningService` and currently uses a mock for development. `scripts/create_institute_admin.mjs` is the reviewable operator-run Admin SDK reference. No function is deployed in Phase 3.

## Password-reset requests

Self-service and authorized managed recovery use Firebase Authentication password-reset emails; no service retrieves an existing password. Managed Super Admin-to-Institute Admin and same-institute Institute Admin-to-Teacher requests append a generic, rules-validated audit entry before sending. The audit entry stores actor/target IDs only and must never contain an email, password, reset link, action code, or token. See `docs/password-recovery.md`.

## Phase 5–6 academic and attendance boundary

Academic institute administration uses validated repository transactions for class/student reservations. QR secrets, session lifecycle, attendance writes, corrections, trusted timestamps, and attendance audits remain backend-only. Flutter release builds use unavailable implementations until callable functions have been reviewed and deployed.

The review-only transaction is in `scripts/attendance_backend_reference.mjs`; its pure validation helpers and tests are under `scripts/lib` and `scripts/tests`. See `docs/phase-5-6-academic-attendance.md` for the QR hash design, idempotent record identity, offline limitation, and manual deployment checklist. Do not export or deploy the reference file directly.

## Phase 7 callable boundary (review only)

This directory now contains a review-only callable wrapper for parent
projection administration. It requires Firebase Authentication and App Check,
revalidates the active Institute Admin and institute for every operation, uses
hashed rate-limit/idempotency keys, returns safe errors, and stores only safe
backend audit metadata.

The deployment source is now self-contained. Canonical validation and writer
logic lives in `lib/parent_projection_validation.mjs` and
`lib/parent_projection_writers.mjs`; no production module imports outside this
directory. Operator scripts use compatibility wrappers that only inject their
own Admin SDK sentinel, so there is still one business implementation.
Package-boundary tests stage this directory, reject external
runtime imports, load the staged entry point, and verify all eight exports.

This is still review-only, not production-ready. Human review must select a
region, validate Android App Check in staging, approve operational limits and
retention, and validate Node 22 in CI or an equivalent runtime before any
deployment. See `docs/phase-7-functions-production-review.md`.

Local tests from the repository root:

```powershell
npm.cmd --prefix Firebase\functions test
npm.cmd --prefix Firebase\functions run test:package

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

firebase.cmd emulators:exec --only firestore `
  --project attendiqo-system --config Firebase\firebase.json `
  "npm.cmd --prefix Firebase\functions run test:integration"

firebase.cmd emulators:exec --only auth,firestore,functions `
  --project attendiqo-system --config Firebase\firebase.json `
  "npm.cmd --prefix Firebase\functions run test:emulator-smoke"
```

The Functions Emulator may use the host Node version; production review must
validate Node 22. App Check emulator results prove missing-token rejection but
do not replace testing configured Android App Check providers in staging.
