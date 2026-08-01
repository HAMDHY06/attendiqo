# Attendiqo project instructions

- Use Flutter and Dart with null safety, strong typing, and Material 3.
- Maintain both apps in this monorepo and keep their Android package names unchanged.
- Reuse shared models, validators, repository contracts, and service contracts from `packages/attendiqo_shared`.
- Do not add student photo fields, photo collection, Firebase Storage, or other student photo storage.
- Do not use phone OTP. Use Firebase email/password authentication.
- Never hardcode passwords, credentials, Admin SDK keys, provider tokens, or private configuration.
- Keep optional SMS disabled by default and use the mock SMS provider during development.
- Attendance persistence must succeed independently when notification or SMS delivery is disabled or fails.
- Maintain institute-based isolation in repositories, backend authorization, queries, and tested Firestore rules.
- Parent access is limited to approved linked students; teachers are limited to assigned classes.
- Super Admin authorization must use server-managed custom claims and secure provisioning.
- Write unit and widget tests for business rules and routing.
- Run `flutter analyze` and `flutter test` in both apps and the shared package after changes.
- Do not implement multiple major development phases in one task without validation.
