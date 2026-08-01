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
- Firestore rules currently deny all client access. Replace them only with emulator-tested role and institute rules.
- Student photographs and Firebase Storage are intentionally absent.

## Notifications and SMS

FCM is the primary alert channel. Reliable sending must occur through Cloud Functions or another trusted backend. Mobile clients contain interfaces and mocks only.

SMS is optional, paid, and disabled by default. `MockSmsService` never contacts an external service. Attendance persistence is intentionally separate from delivery, so push or SMS failure cannot roll back attendance. Notify.lk credentials must be stored only in backend secret management.

## Authentication and roles

Both apps listen to Firebase Authentication state, load `users/{uid}`, validate `active`, validate institute assignment, and route by the shared typed role enum. Attendiqo accepts `superAdmin`, `instituteAdmin`, and `teacher`; Attendiqo Connect accepts only `parent`. Cross-app accounts receive an explicit message and cannot enter the wrong app. See `docs/phase-2-authentication.md` for the profile schema, rules-test command, password-change security note, and review-only deployment command.

The first Super Admin is never created in a mobile app. Review `scripts/README.md` and the one-time `scripts/provision_super_admin.mjs`; it requires external Application Default Credentials and explicit project confirmation and must not be run during ordinary development.

## Continuous scanner architecture

The shared package prepares attendance sessions, entry/departure events, statuses, corrections, device IDs, opaque QR contracts, and duplicate-scan cooldown. The future scanner stays open after each automatic valid scan. Camera access is intentionally not implemented in this foundation.

## Remaining manual Firebase steps

1. Enable Email/Password in Firebase Authentication; do not enable phone authentication.
2. Verify both Android apps and SHA fingerprints in project `attendiqo-system`.
3. Run and test role/institute Firestore rules in the Emulator Suite before replacing deny-all rules.
4. Add required composite indexes when real query designs are finalized.
5. Provision the first Super Admin through a one-time, audited Admin SDK process using server-managed claims.
6. Select a trusted backend for FCM and optional SMS, then configure secrets outside the apps.
7. Configure FCM notification permissions, token rotation, deep links, and Android notification channels.
8. Review all policy drafts with qualified legal/privacy counsel before publication.

## Future stages

Proceed one validated phase at a time: authentication and roles; institute management; teacher/class/student management; opaque QR generation; continuous scanning; attendance reports; secure parent linking; parent dashboard; FCM backend; optional SMS; hardened rules and deployment.

Recommended next task: **Implement secure Firebase email/password authentication, user profiles, role definitions, and role-based routing for Attendiqo and Attendiqo Connect.**
