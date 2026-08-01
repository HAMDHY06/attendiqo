# Phase 3: Super Admin institute management

Status: implemented foundation; Firebase deployment requires human review.

## Scope

Phase 3 adds the Attendiqo Super Admin dashboard, institute search/filter/create/detail/edit/status screens, notification and optional SMS availability controls, Institute Admin listing/provisioning UI, dashboard statistics, and audit history. Teachers, classes, students, attendance, parent linking, notification delivery, and real SMS remain out of scope.

## Collections

- `institutes/{instituteId}` stores the typed institute record. `instituteCode` is immutable; `smsUsedThisMonth` is backend-managed and client-immutable.
- `institute_codes/{UPPERCASE_CODE}` is an immutable reservation used in the same transaction as institute creation to enforce uniqueness.
- `users/{uid}` stores Institute Admin profiles using the shared `UserProfile`; passwords are never stored.
- `audit_logs/{auditLogId}` stores append-only, non-sensitive administrative events.
- `sms_settings/{instituteId}` is reserved for normalized future SMS policy documents.
- `sms_usage/{instituteId}` is readable to authorized roles but writable only by a trusted backend.

Institute records contain `instituteId`, `instituteCode`, `name`, `address`, `contactNumber`, `email`, `active`, typed `status`, push/SMS policy fields, usage, and creation/update metadata. New institutes enable future push availability but default SMS and paid-extra SMS to off.

## Authorization

Firestore institute creation/list/update requires the verified Authentication custom claim `superAdmin: true`; a writable Firestore role field is insufficient. Active Institute Admins may read only their own institute and permitted management profiles. Teachers and parents cannot read institute-management documents. Institutes cannot be deleted by mobile clients. Audit logs cannot be updated/deleted, privileged user profiles cannot be created by clients, and usage counters cannot be changed by ordinary clients, including Super Admin mobile clients.

The rules keep every unrelated collection denied. Run the emulator suite before considering deployment.

## Institute Admin creation

The app invokes the shared `InstituteAdminProvisioningService`. Development uses `MockInstituteAdminProvisioningService`, which contacts no external service. Production must replace it with a reviewed callable backend. The reference `scripts/create_institute_admin.mjs` verifies the acting custom claim and active profile, validates an existing institute, creates the Authentication user, assigns role/institute claims, creates an active profile with `mustChangePassword: true`, and appends an audit record.

The generated policy-compliant temporary password is displayed only in the successful interactive response. It is not stored in Firestore or audit logs. A partial database failure removes the newly created Authentication account. See `scripts/README.md` for the exact procedure.

## Review-only commands

```powershell
cd Firebase
firebase emulators:exec --only firestore "npm --prefix tests test"

# Run only after rule/index review and explicit human approval:
firebase deploy --only firestore:rules,firestore:indexes --project attendiqo-system
```

Do not deploy Cloud Functions in this phase.
