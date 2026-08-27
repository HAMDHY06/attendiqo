# Phase 7: Attendiqo Connect

Status: the secure parent-facing shell now has a projection-only repository and
controller layer for linked children, safe child/class profiles, attendance,
and public institute identity. Nothing is deployed. Real data appears only when
the trusted writers and reviewed Rules/indexes are deployed; otherwise the UI
keeps explicit unavailable states.

Connect authenticates only active `parent` profiles through the shared
authentication flow. The mobile shell provides Home, Children, Attendance,
Notices, and Profile with lazy tab construction and state retention. It shows
clear unavailable states rather than fabricated child or attendance data.

Parent data must be written by a reviewed trusted backend into read-only
projections. Mobile clients cannot create links, write attendance, or edit
notices.

## Connect repository and state model

`FirestoreParentProjectionRepository` reads the signed-in parent's own user
profile, deterministic `parent_student_links`, and parent-safe projection
collections only. It never accepts a parent UID from UI code and never reads
raw students, classes, institutes, teachers, attendance sources, audit logs, QR
data, or backend operational state.

The trusted writer maintains `users/{parentUid}.parentLinkedStudentIds` from the
same authoritative active-link set used for `parent_access_scopes`. The field is
protected by Rules and is only a discovery index; every deterministic link read
must still pass the strict link Rule, active-institute check, and projection
institute match. This avoids weakening Rules merely to support a collection
list query. Link revocation or institute migration updates the discovery index
and removes the child from live state.

`ParentDataController` owns one link/profile graph and child-scoped class,
Today-attendance, history/summary-attendance, notice, and institute
subscriptions. A child switch increments a scope generation, cancels old
listeners, and resets all child data to Loading before the new subscriptions
can emit. Logout clears the selection and cached projections. State is explicit:
Loading, Ready, Empty, Unavailable, or Error; missing trusted data is never
converted into attendance zeroes.

Home, Children, Attendance, Notices, and Profile now render injected projection
data. Phone NavigationBar, tablet NavigationRail, lazy tab creation, preserved
visited-tab state, and Android Back-to-Home behavior remain intact. Internal
student, institute, class, notice, and attendance IDs are not rendered.

The real Firestore notice stream remains intentionally unavailable. Emulator
validation proved that request-time expiry Rules cannot safely authorize the
planned broad list queries. A parent-specific trusted notice-feed index or
read callable must be reviewed before enabling real notices; the strict
get/list Rule was not weakened.

## Trusted synchronization

Reusable operations live in
`Firebase/functions/lib/parent_projection_writers.mjs`; the
top-level `parent_projection_backend_reference.mjs` remains explicitly
review-only and reaches the canonical module through a compatibility re-export.
The chosen strategy is explicit trusted transactions invoked by a
future authenticated callable backend, supplemented later by event-driven
source triggers and scheduled reconciliation. Link creation writes the link,
student projection, derived access scope, and audit atomically. Revocation
marks the link inactive and recomputes the remaining scope without deleting
history. Student/class/institute changes are sanitized from authoritative
sources. Attendance summaries require the still-undeployed trusted attendance
backend. Notices use validated institute-scoped targets.

All operations are retry-safe, version guarded, server-timestamped, and reject
cross-institute references. A backend-only migration invalidator revokes old
links and recomputes every affected parent scope before a moved student's new
projection is written; it must be invoked only by trusted synchronization, not
by a parent client. Its review-only administrative callable derives and checks
the current student institute before invoking it. Deployment still requires
staging App Check validation, event triggers,
reconciliation, monitoring, and production-environment integration tests.

The canonical writer audit also closes the remaining projection-specific trust
gaps: link creation recomputes access scope from active links instead of
appending to cached scope, student class IDs are verified against authoritative
same-institute active classes, class schedule overrides are derived from
non-expired `class_schedule_changes`, and attendance summary IDs are always
derived from student/date/class source fields. Attendance synchronization
revalidates the student, class, and active institute and appends a safe audit.
Suspended institute identity can be reflected only through the internal
trusted-system reconciliation option; that option is not exposed by a callable.

## Review-only callable trust boundary

`Firebase/functions/index.mjs` exports eight v2 callable handlers for link
creation/reactivation, revocation, student/class/attendance/notice/institute
projection synchronization, and student-institute-move invalidation. Handlers
reuse the self-contained canonical Functions writer; projection logic is not
duplicated.

The request path is: Firebase callable verification, explicit Admin SDK bearer
ID-token verification and UID match, App Check enforcement, hashed rate-limit
transaction, source-derived institute lookup, active same-institute Institute
Admin authorization, hashed idempotency claim, canonical writer transaction,
and a safe completion/denial audit.

The local default is 20 requests per actor and operation per minute.
`backend_rate_limits` stores only an actor hash, operation, count, bucket, and
expiry. `backend_idempotency` stores an actor hash, operation, state, safe
result, and expiry. Completed keys replay safe success without repeating the
writer. No request payload is stored.

Errors use stable callable codes including `unauthenticated`,
`permission-denied`, `invalid-argument`, `failed-precondition`,
`resource-exhausted`, `aborted`, `not-found`, and `internal`. Responses never
include stack traces, internal paths, tokens, credentials, email, phone, or
request identifiers. `backend_callable_audits` stores only operation,
allowed/denied outcome, safe code, hashed actor, verified institute ID, and a
server timestamp. Rules deny all mobile access to these backend collections.

This remains review-only. Package-boundary tests now prove every production
relative import resolves inside `Firebase/functions`, a staged copy loads, and
all eight callable exports exist. App Check providers still need staging
validation, TTL policies remain unconfigured recommendations, and Node 22 must
be validated outside the local Node 24 emulator fallback before deployment.
Operational review details are in `phase-7-functions-production-review.md`.

## Validation snapshot (2026-08-02)

- Callable/package/runtime unit tests: 8 passed.
- Callable writer/Firestore integration tests: 14 passed.
- Auth/Functions callable-protocol smoke tests: 2 passed.
- Existing backend Node tests: 24 passed.
- Firestore Rules Emulator tests: 55 passed.
- Shared Flutter tests: 57 passed; analyzer clean.
- Attendiqo tests: 52 passed; analyzer clean.
- Attendiqo Connect tests: 22 passed; analyzer clean.
- Dependency audit: 7 moderate transitive findings; no safe non-breaking fix.
- Secret scan and `git diff --check`: passed.
- `git diff --check`: passed.

No Functions, Rules, indexes, or application build was deployed.
# Staging-readiness update

The reviewed Functions package now includes a server-side `listApplicableParentNotices` callable. It is App Check protected, rate-limited by a hashed actor key, requires an active parent profile and derives notice scope from active trusted links and safe child projections. It never accepts a parent UID, student ID, class ID or institute ID from the caller. The Connect repository may use the callable only when the reviewed backend has been deployed; otherwise it must retain the existing unavailable notice state.

`users/{parentUid}.parentLinkedStudentIds` remains a trusted discovery index, not a source of truth. The review-only bounded migration utility recomputes it from active deterministic `parent_student_links`, skips malformed/cross-institute links, supports dry-run and protected checkpoints, and prints aggregate progress only. See [phase-7-staging-plan.md](phase-7-staging-plan.md).
