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
