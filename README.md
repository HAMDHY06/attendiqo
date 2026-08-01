# Attendiqo Attendance System

Attendiqo is an Android-first Flutter attendance platform developed by **HamdhyTech**. Phase 2 adds secure Firebase email/password authentication, typed user profiles, authentication-state listeners, forced password change, and role-based routing. Institute and attendance features are not implemented yet.

It contains:

- **Attendiqo** (`com.hamdhytech.attendiqo`) for Super Admins, Institute Admins, and teachers.
- **Attendiqo Connect** (`com.hamdhytech.attendiqo.connect`) for parents and guardians.
- **attendiqo_shared**, a reusable Dart package for typed models, validation, contracts, and business rules.

Support: `dev.hamdhytech@gmail.com`  
Firebase project: `attendiqo-system`

## Repository structure

```text
apps/attendiqo/                 Main Flutter app
apps/attendiqo_connect/         Parent Flutter app
packages/attendiqo_shared/      Shared domain package
firebase/                       Secure rules, indexes, and backend placeholders
Firebase/                       Supplied Android Firebase client configuration
Requirements/                   Original project specifications
Logos/                          Supplied branding assets
docs/                           Architecture and policy drafts
scripts/                        Provisioning guidance only
```

The original project supplied a singular `Logo/` directory. Its files are preserved in the source location and copied into the required `Logos/` directory and app asset folders. On Windows, `Firebase/` and `firebase/` cannot exist as distinct case-only directory names, so the preserved client configuration and backend rules/functions live together under `Firebase/`; references using `firebase/` resolve to the same directory on this platform.

## Requirements and setup

Use Flutter stable 3.44 or later and Dart 3.12 or later.

```powershell
cd packages/attendiqo_shared
flutter pub get
flutter analyze
flutter test

cd ../../apps/attendiqo
flutter pub get
flutter analyze
flutter test
flutter run

cd ../attendiqo_connect
flutter pub get
flutter analyze
flutter test
flutter run
```

## Firebase client configuration

Both apps use the existing Firebase project. The expected files are:

- `Firebase/Admin/google-services.json` -> `apps/attendiqo/android/app/google-services.json`
- `Firebase/Connect/google-services.json` -> `apps/attendiqo_connect/android/app/google-services.json`

These are Android client configuration files, not Firebase Admin SDK service accounts. This repository keeps the supplied files for a controlled private project. For a public repository, untrack them and inject them through private CI artifacts. Never place an Admin SDK service-account file in either mobile app.

Firebase initialization is prepared. The apps start in safe foundation mode if Firebase cannot initialize; they do not request protected data in that state.

## Security and secrets

- Authentication will use email/password, never phone OTP.
- Do not store readable passwords or roles editable by clients.
- Use trusted backend custom claims for Super Admin.
- Keep real `.env` files, service accounts, signing keys, and provider credentials outside Git.
- `.env.example` contains names only. Store deployed secrets in Firebase/Google Cloud Secret Manager.
- Firestore rules allow only the emulator-tested authentication, institute administration, and same-institute teacher-management paths; every unrelated collection remains denied.
- Student photographs and Firebase Storage are intentionally absent.

## Notifications and SMS

FCM is the primary alert channel. Reliable sending must occur through Cloud Functions or another trusted backend. Mobile clients contain interfaces and mocks only.

SMS is optional, paid, and disabled by default. `MockSmsService` never contacts an external service. Attendance persistence is intentionally separate from delivery, so push or SMS failure cannot roll back attendance. Notify.lk credentials must be stored only in backend secret management.

## Authentication and roles

Both apps listen to Firebase Authentication state, load `users/{uid}`, validate `active`, validate institute assignment, and route by the shared typed role enum. Attendiqo accepts `superAdmin`, `instituteAdmin`, and `teacher`; Attendiqo Connect accepts only `parent`. Cross-app accounts receive an explicit message and cannot enter the wrong app. See `docs/phase-2-authentication.md` for the profile schema, rules-test command, password-change security note, and review-only deployment command.

The first Super Admin is never created in a mobile app. Review `scripts/README.md` and the one-time `scripts/provision_super_admin.mjs`; it requires external Application Default Credentials and explicit project confirmation and must not be run during ordinary development.

## Password recovery

Both applications retain Firebase Authentication email-based Forgot Password flows with non-enumerating confirmation text. Super Admins can request reset emails for Institute Admins, and Institute Admins can request reset emails only for Teachers in their own institute. Managed requests create append-only, non-sensitive audit entries. Existing passwords are never displayed or stored, accounts are not recreated when a temporary password is lost, and the `mustChangePassword` first-login flow is preserved. See `docs/password-recovery.md`.

## Super Admin institute management

The verified Super Admin area now provides institute dashboard statistics, search/filtering, lifecycle controls, notification/SMS availability settings, Institute Admin account preparation, and audit history. Institute codes are uppercase, immutable, and reserved transactionally through `institute_codes`. Client code cannot change SMS usage counters or create privileged user profiles.

The Flutter app uses a local mock for Institute Admin provisioning. Production account creation must use a reviewed trusted backend; the secure Admin SDK reference and exact operator procedure are in `scripts/create_institute_admin.mjs` and `scripts/README.md`. See `docs/phase-3-institute-management.md` for the architecture and review-only deployment command.

## Institute Admin teacher management

Active Institute Admins now receive a responsive Teacher Management area scoped to their own institute. It supports teacher search/status filters, secure creation preparation, permitted edits, typed permissions, disable/reactivate actions, reset-email requests, first-login status, and teacher audit history. Verified Super Admins have cross-institute monitoring with an institute filter.

Privileged creation is never performed with client Admin credentials. Debug builds use an isolated mock, release builds remain unavailable until backend deployment, and `scripts/create_teacher.mjs` provides a reviewed operator reference that emits a temporary password only once. See `docs/phase-4-teacher-management.md` and `scripts/README.md`.

## Continuous scanner architecture

The shared package and Attendiqo app now prepare academic management, secure opaque QR issuance, attendance sessions, entry/departure events, corrections, device IDs, continuous camera scanning, cooldown, CSV/PDF reports, and print-friendly QR cards. Debug builds use an in-memory trusted-service mock. Release QR and attendance operations remain unavailable until the reviewed backend is implemented; direct mobile writes to the sensitive collections are denied. See `docs/phase-5-6-academic-attendance.md`.

## Remaining manual Firebase steps

1. Enable Email/Password in Firebase Authentication; do not enable phone authentication.
2. Verify both Android apps and SHA fingerprints in project `attendiqo-system`.
3. Review the Phase 5–6 Firestore rules and run the Emulator Suite before deployment.
4. Review and deploy the academic/attendance composite indexes when the rules are approved.
5. Provision the first Super Admin through a one-time, audited Admin SDK process using server-managed claims.
6. Implement and review callable QR/attendance services before enabling release attendance. Then select a trusted backend for FCM and optional SMS, with secrets outside the apps.
7. Configure FCM notification permissions, token rotation, deep links, and Android notification channels.
8. Review all policy drafts with qualified legal/privacy counsel before publication.

## Future stages

Proceed one validated phase at a time: secure parent linking; parent dashboard/history; schedule notifications; FCM backend; optional SMS; hardened rules and deployment.

Recommended next task: **Implement Attendiqo Connect parent registration, secure student linking, multiple-child support, parent attendance dashboard, attendance history, and class-schedule notifications.**
