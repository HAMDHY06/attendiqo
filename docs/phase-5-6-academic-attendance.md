# Phase 5–6: academic management and QR attendance

Status: implementation foundation complete; production trusted attendance backend is **not deployed**.

## Milestone A

The shared package defines typed `AcademicClass`, `ClassScheduleChange`, `Student`, and `ClassStudentAssignment` models. Class codes and student numbers are normalized uppercase values and use deterministic institute-scoped reservation documents. Classes and students are retained with lifecycle statuses rather than deleted.

Normal schedules remain on the class. A `ClassScheduleChange` stores old and new time/location values for one date. `ClassScheduleResolver` overlays only an active one-time change, so future attendance sessions retain the effective schedule and its change ID without overwriting the normal schedule.

A student may have many `class_students` documents. The deterministic assignment ID is `<classId>_<studentId>`, making duplicate active enrolment detectable while keeping attendance class- and session-specific. Normal schedule overlap is warned, not silently blocked; an Institute Admin must provide a reason and the approval metadata is auditable.

The application provides academic overview, searchable/filterable class and student lists, creation/edit forms, teacher assignment, details, schedule changes/cancellation, enrolment/removal, parent-contact visibility, status controls, and academic audit views. Teachers see only assigned class documents. Full student documents are not opened to teachers directly in Firestore because a `/students/{id}` rule cannot prove an arbitrary assigned-class relationship; production teacher student views must use a trusted, redacted assigned-class projection/callable. This is intentionally stricter than institute-wide access.

Firestore Rules also cannot safely iterate an arbitrary `teacherIds` list and validate every referenced user. Direct mobile class writes are therefore limited to zero or one same-institute primary teacher. The typed model/UI supports multiple teachers, but saving multi-teacher assignments in release must use a trusted callable transaction that validates every UID. This avoids a cross-institute secondary-teacher injection gap.

## Milestone B

### QR design

`SecureStudentQrService` uses `Random.secure()` to create 256-bit random values. The printable payload is `attendiqo://student/<opaque-token>`. Firestore stores a SHA-256 lookup hash and metadata in `qr_tokens/{tokenHash}`; it must never store the printable raw token. Regeneration creates a higher `qrVersion` and revokes the old hash. Disable/enable is backend-controlled.

The raw payload is returned once for printing/sharing. Because hashes are one-way, an existing card cannot be reconstructed later: regenerate it to issue a replacement. QR PDF cards include institute name, student name, student number, and the QR only. Parent mobiles, addresses, passwords, and attendance history are excluded.

### Trusted attendance transaction

Flutter depends on `AttendanceService`. Debug builds use `MockAttendanceService`; release builds use `UnavailableAttendanceService` until a reviewed callable backend exists. `scripts/attendance_backend_reference.mjs` demonstrates the required Admin SDK transaction but is not a deployable function export.

The trusted service must:

1. Verify the caller ID token and active profile. A Super Admin additionally needs the verified custom claim.
2. Load the open session, active institute, active class, and effective schedule.
3. Confirm an Institute Admin is in the institute, or a teacher is assigned and has `canTakeAttendance`.
4. Hash the incoming opaque token, resolve the exact QR document, and verify enabled state/version/institute.
5. Verify the active student and deterministic active class enrolment.
6. Write `attendance_records/<sessionId>_<studentId>` transactionally using server time.
7. Reject duplicate entry, departure before entry, and duplicate departure within that session only.
8. Append a non-sensitive audit entry. Do not store or log the raw QR payload.
9. Trigger future FCM/SMS only after the attendance transaction is confirmed, and never roll attendance back when delivery fails.

The continuous scanner remains open after success and needs no per-student confirmation. It displays selected class/date/effective time/mode, camera state, confirmed count, class total, latest student/result/time, pause/resume, manual attendance, and finish controls. A token-specific cooldown prevents repeated camera reads without slowing different students.

Offline support is deliberately minimal and safe: the UI exposes online/offline state and never labels an offline attempt as confirmed. It does not maintain a production queue yet. Durable queue idempotency, reconnection sync, and conflict resolution must be implemented and load-tested in the trusted backend before enabling offline recording.

### Reports

The typed report layer provides daily/session records, entry/departure times, status/late minutes, percentage calculation, CSV generation, PDF generation, and export permission checks. The current debug UI reports the active in-memory session. Production date-range/class/student queries must be implemented through the trusted service before release. `AttendanceExportService` is the future Google Sheets boundary; Sheets synchronization is not implemented.

## Collections and indexes

Milestone A uses `classes`, `class_codes`, `class_schedule_changes`, `students`, `student_numbers`, `class_students`, and `audit_logs`. Milestone B prepares `qr_tokens`, `attendance_sessions`, `attendance_records`, `attendance_corrections`, and `audit_logs`.

Composite indexes cover institute/status academic queries, both class-to-student and student-to-class active assignments, class schedule changes by effective date, sessions by class/date, records by session/student and student/date, and audit logs by institute/date.

## Package decisions

- `mobile_scanner`: live QR camera detection.
- `qr_flutter`: Material-compatible on-screen QR rendering.
- `pdf` and `printing`: print-friendly QR cards, PDF reports, and platform share/print flow.
- `crypto`: SHA-256 lookup hashing.
- Flutter `HapticFeedback`: success vibration without another plugin.
- CSV is generated by the small typed exporter, avoiding an unnecessary package.

## Manual Firebase/backend steps

1. Review this document, `firestore.rules`, indexes, Emulator tests, and the reference transaction with a Firebase security reviewer.
2. Implement callable functions for QR administration, session lifecycle, scanning, manual attendance, corrections, and filtered reports. Use App Check, Authentication ID-token verification, Admin SDK transactions, server timestamps, rate limits, idempotency, and structured non-sensitive logs.
3. Put runtime credentials in Firebase/Google Cloud managed identity and Secret Manager. Never add service-account files to this repository or Flutter.
4. Add integration tests against Auth/Firestore/Functions emulators, including concurrency, retries, revoked QR, and offline conflict cases.
5. Only after human review, deploy rules/indexes:

   ```powershell
   firebase deploy --only firestore:rules,firestore:indexes --project attendiqo-system
   ```

6. Do **not** deploy `scripts/attendance_backend_reference.mjs`. Convert reviewed logic into a real callable implementation, test it, and only then run an explicitly approved functions deployment.

No production FCM or SMS is sent in this phase. Attendiqo Connect remains unchanged apart from shared package compatibility.
