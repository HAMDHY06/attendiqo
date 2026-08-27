# Parent security model

Only authenticated, active parent profiles may use Attendiqo Connect. Parent
links are read-only to their owning parent and must be created by a trusted
backend. Parent projections are read-only. Parents cannot access audit logs,
raw QR tokens, full student documents, full institute documents, other
parents, management profiles, or write attendance.

Rules use both the deterministic active link and a backend-only
`parent_access_scopes/{uid}` document. Access also requires an active parent
profile and active institute. A revoked final link atomically empties the
scope, immediately removing all projection reads while retaining historical
attendance data.

Notices are readable only when active, non-expired, and targeted to the linked
institute, student, or class. Projection writes, link writes, and access-scope
reads/writes are denied to every mobile client. Admin SDK writers bypass Rules,
so their callable wrapper must independently verify ID tokens, App Check,
active actor/profile/institute state, institute scope, exact schemas, and rate
limits before deployment.

The Phase 7 review boundary now performs both callable-platform authentication
and an explicit Admin SDK bearer-token verification whose UID must match the
callable context. App Check is enforced by the v2 handler and rechecked by the
testable core. Every operation derives institute scope from an authoritative
student, class, attendance, link, notice, or institute record; a client-provided
institute ID alone never authorizes access.

Rate-limit, idempotency, and callable-audit documents use hashed actor IDs and
contain no payloads, email addresses, mobile numbers, tokens, or credentials.
Firestore Rules deny them to parents, teachers, Institute Admin clients, and
Super Admin clients. Admin SDK access is limited to the review-only boundary.

The canonical validators and writers are inside the Functions deployment root.
Scripts only re-export validation and inject their local Admin SDK sentinel into
the canonical writers. A package-boundary test rejects any production relative
import that escapes that root and loads a staged copy before release review.

Projection writers independently reject cross-institute or inactive class and
attendance sources. Parent access scopes are rebuilt from active links, not
trusted as client or cached input. The callable never exposes the internal
`trustedSystem` option used to reflect a suspended institute public status.
Parents remain unable to invoke any writer or read its operational/audit state.

## Mobile read boundary

Connect derives the Firebase UID internally. UI code cannot supply a parent UID
and cannot select an unlinked child. A protected
`users/{uid}.parentLinkedStudentIds` array discovers deterministic link IDs;
parent self-updates cannot change it. Strict per-link gets still verify owner,
active link, active institute, deterministic ID, and matching student
projection. Derived reads additionally require the backend-only access scope.

Child changes cancel all previous subscriptions and clear profile, class,
attendance, notice, and institute state before new data is accepted. Generation
guards discard late child-A emissions after selecting child B. Logout clears
selection and cached projection state.

Attendance queries include both student and institute equality constraints and
server-side date bounds. Class and institute reads are deterministic gets.
There is no broad raw collection read. The planned notice list query was not
enabled because request-time publication/expiry enforcement could not be proven
securely in Rules query evaluation; Connect reports an explicit unavailable
state pending a trusted notice-feed boundary.
# Staging callable boundary

The parent notice feed uses a callable rather than a client Firestore list query because target, publication and expiry predicates are evaluated together with trusted server time. The callable verifies Firebase Auth UID matching and App Check, checks the active parent profile, derives active linked-child scope itself, limits results and emits a safe aggregate callable audit. It returns only parent-safe notice fields and no target identifiers. Missing or undeployed Functions remain an explicit unavailable state in Connect.
