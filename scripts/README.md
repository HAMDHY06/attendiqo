# Secure first Super Admin provisioning

Do not run `provision_super_admin.mjs` until the Firebase project, operator identity, and Admin credentials have been reviewed. It is never called by either Flutter application.

## Exact manual procedure

1. Enable Email/Password authentication in Firebase project `attendiqo-system`.
2. On a trusted administrator workstation, install Node.js 20 or later.
3. Obtain a short-lived, least-privilege Admin SDK credential or use approved Application Default Credentials. Keep it outside this repository. Never copy a service-account JSON file into `scripts/`, `apps/`, or Git.
4. Set `GOOGLE_APPLICATION_CREDENTIALS` only in the trusted terminal session when a reviewed external JSON credential is required.
5. From `scripts/`, run `npm ci` after reviewing `package-lock.json`, or run `npm install` once to create and review the lockfile.
6. Run `node provision_super_admin.mjs --confirm-project=attendiqo-system`.
7. Enter the Super Admin email at the interactive prompt. If the Authentication account does not exist, enter the initial password through the hidden terminal prompt. The password is not printed or written to disk.
8. Verify in Firebase Authentication that the account exists and is enabled.
9. Verify the custom claim with a trusted Admin SDK inspection: `superAdmin: true`.
10. Verify `users/{uid}` contains `role: superAdmin`, `instituteId: null`, `active: true`, and the expected timestamps.
11. Sign in to Attendiqo. A newly created account is forced to replace the temporary password.
12. Revoke/delete the temporary Admin credential, clear the terminal environment variable, and archive a non-sensitive audit record containing only operator, UID, time, and outcome.

The script refuses non-interactive input, requires explicit project confirmation, preserves existing custom claims, refuses to replace a non-Super-Admin profile, and never stores the password.

## Secure Institute Admin provisioning (Phase 3)

The Flutter application uses `InstituteAdminProvisioningService`; its development implementation is local-only and never contacts Firebase. Production provisioning must run in a trusted backend. The reviewed command-line reference implementation is `create_institute_admin.mjs`.

1. Complete and verify the Super Admin procedure above.
2. Create the institute through the Super Admin UI and copy its Firestore document ID.
3. On a trusted administrator workstation, authenticate with approved Application Default Credentials for `attendiqo-system`; keep any service-account file outside this repository.
4. From `scripts/`, run `npm ci` after reviewing the lockfile.
5. Run `node create_institute_admin.mjs --confirm-project=attendiqo-system --actor-uid=<verified-super-admin-uid>`.
6. Enter the existing institute ID, display name, and email interactively.
7. Copy the generated temporary password from the terminal once and deliver it through an approved secure channel. It is never written to Firestore or an audit log.
8. Verify the Authentication user, custom claims, `users/{uid}` profile, and append-only `audit_logs/{id}` entry.
9. Have the administrator sign in and complete the mandatory password-change flow.
10. Clear the terminal and revoke short-lived credentials when finished.

For production, replace this operator-run tool with a reviewed callable HTTPS function that verifies the caller ID token contains `superAdmin: true`, checks the active Super Admin profile, validates the institute and request, rate-limits requests, performs the same Admin SDK writes, and returns the temporary password only in the single successful response. Do not deploy it until code review and emulator/integration testing are complete.

## Secure Teacher provisioning (Phase 4)

The Flutter client calls the `TeacherProvisioningService` abstraction. Debug builds use a non-networked mock; release builds report that the trusted backend is unavailable. Until a reviewed callable backend is deployed, use `create_teacher.mjs` only on a trusted administrator workstation:

1. Verify the target institute is active and the actor is either its active Institute Admin or a verified Super Admin.
2. Use Node.js 20 or later and approved Application Default Credentials for `attendiqo-system`. Keep credential files outside this repository.
3. Review `create_teacher.mjs`, `package-lock.json`, and the validation tests, then run `npm ci` and `npm test` from `scripts/`.
4. Run `node create_teacher.mjs --confirm-project=attendiqo-system --actor-uid=<authorized-actor-uid>`.
5. Enter the institute ID, teacher name, email, and optional phone and employee number interactively. Institute Admin actors cannot target another institute.
6. Copy the generated temporary password once and deliver it through an approved secure channel. It is never persisted or logged by the script.
7. Verify the Authentication account and its `role: teacher` and `instituteId` claims, `users/{uid}`, optional `teacher_employee_numbers/{instituteId_employeeNumber}`, and the `teacherCreated` audit entry.
8. Have the teacher sign in and complete the mandatory password change. If the password is lost, send a reset email; never recreate the account.
9. Clear the terminal, remove any copied password, and revoke short-lived credentials.

The script validates actor and institute state twice, normalizes the email and employee number, checks email and institute-scoped employee-number uniqueness, uses a cryptographically secure password generator, rolls back the Authentication user on Firestore failure, and excludes passwords from Firestore and audit logs.

## Attendance backend reference (Phase 6)

`attendance_backend_reference.mjs` is review-only transaction code, not an operator command and not a deployable Cloud Function export. Its pure helpers validate the `attendiqo://student/<opaque-token>` shape, hash the raw token, validate scan mode/device/session input, enforce Super Admin claims, institute isolation, assigned-teacher access, and `canTakeAttendance`, and generate session-specific record IDs.

Run `npm test` to validate the helpers. For production, port the reviewed logic into callable functions with App Check, Authentication ID-token verification, Admin SDK transactions, rate limiting, server timestamps, non-sensitive structured logs, and emulator concurrency tests. Do not pass service-account credentials to Flutter, and never log or persist the raw QR payload.
