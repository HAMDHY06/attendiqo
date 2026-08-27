# Parent data projections

Status: backend contracts and reviewable Admin SDK writers are implemented but
not deployed. Connect has projection-only readers and shows real data only when
those projections exist; missing services or projections remain unavailable.

## Collections and document IDs

- `parent_student_links/{parentUid}_{studentId}`: `parentUid`, `studentId`,
  `instituteId`, `relationship`, `active`, `createdAt`, `updatedAt`, `createdBy`,
  nullable `revokedAt`/`revokedBy`, and integer `sourceVersion`.
- `parent_student_profiles/{studentId}`: `studentId`, `instituteId`, `fullName`,
  `studentNumber`, nullable `grade`, `active`, `classIds`, nullable
  `publicProfileImageUrl`, `updatedAt`, and `sourceVersion`.
- `parent_class_profiles/{classId}`: `classId`, `instituteId`, `className`,
  `subject`, nullable `grade`, approved `teacherDisplayName`, nullable `room`,
  `normalSchedule`, nullable `effectiveSchedule`, `active`, `updatedAt`, and
  `sourceVersion`.
- `parent_attendance_summaries/{studentId}_{YYYY-MM-DD}_{classId}`:
  `summaryId`, `studentId`, `instituteId`, `classId`, `attendanceDate`, `status`,
  nullable `entryTime`/`exitTime`, `late`, `currentPresenceState`, `updatedAt`,
  and `sourceVersion`. The authoritative attendance writer supplies the stable
  `attendanceDateKey`; a timestamp string is never used as an ID.
- `parent_notices/{noticeId}`: `noticeId`, `instituteId`, `title`, `message`,
  `priority`, `publishedAt`, nullable `expiresAt`, `active`, `targetType`,
  `targetStudentIds`, `targetClassIds`, `updatedAt`, and `sourceVersion`.
- `institute_public_profiles/{instituteId}`: `instituteId`, `displayName`,
  nullable `logoUrl`, `publicPhone`, `publicEmail`, and `publicAddress`, plus
  `status`, `updatedAt`, and `sourceVersion`.
- `parent_access_scopes/{parentUid}` is a backend-only derived authorization
  index containing active student, class, and institute IDs. Clients cannot
  read or write it. It lets Rules prove class/institute access without unsafe
  collection scans and is atomically recomputed on revocation.
- `users/{parentUid}.parentLinkedStudentIds` is a protected, sorted discovery
  index maintained by the same trusted transactions. Connect watches its own
  profile and then watches deterministic link documents. Parent clients may
  read their own profile but cannot modify this field.

## Privacy boundary

Projection sanitizers use explicit allowlists. They do not copy QR data,
parent/emergency contacts, health or disciplinary notes, reservation data,
teacher contact/permission data, billing/SMS configuration, secrets, or audit
metadata. Full `students`, `institutes`, teachers, attendance sources, QR data,
and audit logs remain denied to parents.

`sourceVersion` is a non-negative authoritative version. Equal versions are
safe retries; lower versions are rejected. Trusted writers use server
timestamps. Source records remain authoritative.

Student projection versions use the newest version from the student and all
of its assignment records, including inactive assignments. This means a normal
assignment removal cannot silently retain a class. Class projection versions
use the newest class or schedule-change version. Active class IDs are accepted
only after the source class is confirmed active, non-archived, same-institute,
and present. Attendance IDs are always
`{studentId}_{YYYY-MM-DD}_{classId}`; a conflicting source-supplied ID is
rejected rather than trusted.

Access scope is recomputed from active parent links and their projections on
link creation/reactivation and revocation. It is never extended from an
unverified cached value. Normal class-assignment removal keeps the inactive
assignment source document so its version participates in stale-write
prevention.

Student projection synchronization also recomputes every affected parent's
class scope. Therefore removing a class assignment removes the class from both
the student projection and Rules authorization; the protected linked-student
profile index remains synchronized at the same time.

## Connect reads and limits

- Own user profile: one live document, used only for authenticated parent
  identity and the protected linked-student discovery index.
- Links: deterministic document gets, maximum 20.
- Student profiles: deterministic document gets, maximum 20.
- Class profiles: deterministic document gets from the selected safe child
  projection, maximum 30; no Teacher profile reads.
- Attendance: `studentId == selected child`, `instituteId == active link`,
  ordered by `attendanceDate DESC`, bounded to 100; Today uses a separate
  date-bounded query limited to 30.
- Institute identity: one deterministic public-profile get per selected
  institute, cached by the selected session graph.
- Notices: no production Firestore list query is enabled. The current strict
  request-time expiry Rule cannot safely authorize the desired broad query;
  Connect returns Unavailable pending a trusted parent-specific feed.

## Synchronization strategy

The implemented strategy is explicit, idempotent trusted transactions behind
the review-only callable boundary. Student, assignment, class, schedule,
attendance, notice, and institute source documents remain authoritative.
Future event-driven triggers and scheduled reconciliation are still required
for automatic production propagation and missing-projection repair. Expired
scheduled overrides are ignored; the next non-expired scheduled change is used.
Notice expiry is enforced by Rules even before later scheduled deactivation.

## Required indexes

- `parent_student_links`: `parentUid ASC, active ASC`.
- `parent_student_links`: `studentId ASC, active ASC` for trusted migration
  invalidation and reconciliation.
- `parent_attendance_summaries`: `studentId ASC, instituteId ASC,
  attendanceDate DESC`.
- `parent_notices`: `instituteId ASC, active ASC, publishedAt DESC`.
- `parent_notices`: `targetStudentIds ARRAY_CONTAINS, active ASC,
  publishedAt DESC`.
- `parent_notices`: `targetClassIds ARRAY_CONTAINS, active ASC,
  publishedAt DESC`.

The three notice indexes remain preparation only and are not currently used by
the Connect repository. No new notice index was added for an unsafe query.
# Discovery-index migration

`users.parentLinkedStudentIds` is a derived, sorted, unique discovery index for an authenticated parent's deterministic link lookups. `parent_student_links` is authoritative. A review-only Admin SDK migration recomputes the full array for each encountered parent so batching cannot drop links; malformed, non-deterministic, missing-projection or cross-institute links are blocked and reported only as aggregate counts. No mobile client can write this index.
