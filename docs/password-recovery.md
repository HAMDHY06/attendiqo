# Password recovery

Status: implemented and emulator-tested. Firebase deployment still requires human review.

## Self-service recovery

Attendiqo and Attendiqo Connect retain their Forgot Password screens. Valid submissions call Firebase Authentication `sendPasswordResetEmail`. A missing Firebase user is treated as a safe successful request so the interface does not reveal whether an unrelated email address exists. Invalid-email, disabled-account, network, loading, and success states use curated messages rather than raw Firebase exceptions.

## Managed recovery

- A verified Super Admin can select an Institute Admin and use **Send Password Reset Email**.
- An active Institute Admin can select a Teacher from the same institute and use **Send Password Reset Email**.
- Institute Admins cannot use the managed flow for another institute, another Institute Admin, a parent, or a Super Admin.
- Disabled profiles are clearly marked and are not sent reset instructions.

Managed recovery writes an append-only `passwordResetRequested` entry for Institute Admin targets or `teacherPasswordResetRequested` for Teacher targets before calling Firebase Authentication. The entry contains actor UID/role, target UID, institute ID, a generic summary, and server timestamp. It contains no email address, password, temporary password, reset link, or token. Firestore rules validate the target role and institute using the protected `users` collection.

Password recovery never displays, retrieves, or stores an existing password. Losing a temporary password is handled by sending a reset email, not by recreating the account. `mustChangePassword` remains unchanged until the existing first-login password-change flow completes successfully.

## Operational note

Enable and configure Firebase Authentication email templates and an authorized continue URL in project `attendiqo-system`. Review sender branding and support contact before production. Firebase Authentication email-enumeration protection should remain enabled where available.
