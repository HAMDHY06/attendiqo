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
