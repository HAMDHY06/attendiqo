# Phase 4: Teacher management

Status: implemented for development and emulator validation. Privileged production provisioning and Firebase deployment remain manual, review-gated operations.

## Scope and architecture

Attendiqo routes an active `instituteAdmin` to the Teacher Management area. Its controller loads only `users` records with `role: teacher` and the actor's immutable `instituteId`. A verified Super Admin can open Teacher Monitoring, load teachers across institutes, and apply an institute filter. Screens cover dashboard metrics, search/status filters, creation, details, permitted edits, permissions, disable/reactivate confirmation, managed password reset, teacher audit history, and the one-time temporary-password result.

`TeacherRepository` separates reads and permitted Firestore transactions from UI state. `TeacherProvisioningService` separates privileged Authentication account creation from the Flutter client. Debug builds use `MockTeacherProvisioningService`; release builds use `UnavailableTeacherProvisioningService` until a reviewed trusted backend is deployed. No Admin SDK credential exists in Flutter.

## Teacher profile and permissions

Teacher accounts remain in `users/{uid}`. Identity fields are `uid`, normalized `email`, required `displayName`, `role: teacher`, and required `instituteId`. Lifecycle fields are `active`, `mustChangePassword`, `status`, and `lastLoginAt`. Administration fields are `createdAt`, `createdBy`, `updatedAt`, and `updatedBy`. `phoneNumber` and institute-scoped `employeeNumber` are optional. `permissions` is a structured map with exactly ten known Boolean keys; unknown keys are rejected.

New profiles default to `active: true`, `mustChangePassword: true`, and `status: pendingFirstLogin`. The first successful required password change transaction changes `mustChangePassword` to false, changes status to `active`, and appends `teacherFirstLoginCompleted`. Passwords never enter Firestore or audit logs.

Employee numbers are optional, uppercase, validated, and reserved transactionally at `teacher_employee_numbers/{instituteId_employeeNumber}`. Reservation documents are protected from direct untrusted creation and mutation.

## Security boundary

Rules deny unauthenticated access and all direct privileged profile creation. A verified `superAdmin` custom claim plus an active Super Admin profile is required for cross-institute monitoring. Active Institute Admins can read and update permitted teacher fields only inside their own active institute. They cannot change role, institute assignment, email, creation fields, last-login timestamp, or `mustChangePassword`. Teachers can read only their own profile and cannot change role, institute, active state, employee number, or permissions. Parent access is denied.

Institute suspension or inactivation disables Institute Admin management access. Audit logs are readable by verified Super Admins and by active same-institute Admins for teacher targets; clients cannot edit or delete them. All unrelated future collections remain denied.

## Password recovery and first login

Institute Admins can send Firebase password-reset email only to active teachers in the same institute; verified Super Admins can do so for any active teacher. The result uses non-enumerating safe text. `teacherPasswordResetRequested` stores only non-sensitive audit metadata. A reset request does not clear `mustChangePassword`.

If a temporary password is lost, use password recovery; never recreate the teacher account. On initial sign-in, authentication routing sends the teacher to the change-password screen before any dashboard. The Teacher role cannot enter Institute Admin or Super Admin screens.

## Trusted provisioning

The reviewed operator reference is `scripts/create_teacher.mjs`. It uses external Application Default Credentials, verifies the actor Auth user/profile and scope, requires an active target institute, checks duplicate Auth email and transactional employee-number uniqueness, generates a policy-compliant password using `node:crypto`, assigns role/institute claims, creates the profile/reservation/audit atomically, and rolls back the Auth user after a Firestore failure. It displays the password exactly once and does not log or persist it.

See `scripts/README.md` for the exact operating procedure. Do not run the script with real credentials during development. A future callable backend must reproduce these checks, verify the caller ID token, rate limit provisioning/reset operations, and return temporary credentials only in the single authorized response.

## Review-only Firebase commands

Run emulator tests first:

```text
cd Firebase
npm --prefix tests ci
firebase emulators:exec --only firestore "npm --prefix tests test" --project attendiqo-system --config firebase.json
```

Only after human review and explicit approval:

```text
firebase deploy --project attendiqo-system --only firestore:rules
firebase deploy --project attendiqo-system --only firestore:indexes
```

No Cloud Function is deployed by Phase 4.
