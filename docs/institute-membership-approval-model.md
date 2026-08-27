# Institute membership and approval model

Status: **Implemented locally — contract foundation only.** This is not deployed and does not replace the current single-institute profile until the migration, trusted approval callable, Rules, UI, and tests are complete.

## Deployable Worker boundary status (2026-08-09)

**Implemented locally / locally tested:** shared membership contracts, active
membership selection, reviewer policy, strict Firestore denials, and legacy
session compatibility while a trusted migration is pending.

**Undeployed / blocked:** the existing Cloudflare Worker authenticates with an
end-user Firebase ID token. That token is intentionally subject to Firestore
Rules, so it cannot create or approve membership records while those records
remain callable-only. Forwarding the token does not create a privileged backend
boundary.

Do not solve this by allowing broad client writes to membership collections or
by treating a join code as a credential. A deployable Worker approval flow
requires a separately approved server-to-server Firebase credential with the
least necessary Firestore scope, stored only as a Cloudflare Worker secret.
Until that external credential and its rotation policy are approved, membership
approval endpoints remain review-only and undeployed.

The mobile apps may continue using the documented legacy assignment only for
existing accounts during the migration window. Once an account has membership
records, inactive, pending, rejected, suspended, or revoked records must not
fall back to legacy access.

## Purpose

One Firebase account may hold independent memberships in more than one institute. A visible institute join code identifies the institute for a request; it is **not a password, invite secret, or access grant**.

## Future collections

```text
institute_join_codes/{code}
  instituteId, active, createdAt, updatedAt

institute_memberships/{uid_instituteId}
  uid, instituteId, role, status, requestedAt,
  approvedAt, approvedBy, reviewedAt, reviewedBy

institute_join_requests/{requestId}
  uid, instituteId, requestedRole, status,
  requestedAt, reviewedAt, reviewedBy
```

No raw email, phone number, password, student record, or approval reason belongs in these documents.

## Workflow

1. A signed-in user enters a visible institute join code.
2. A trusted backend resolves the code and creates an idempotent `pending` request.
3. Pending users see only a waiting screen and no institute data.
4. Super Admin approves Institute Admin membership requests.
5. An active Institute Admin for that institute approves Teacher and parent-related requests.
6. Only the trusted approval transaction creates or activates a membership.
7. A user can select one active institute membership for a session; switching clears all institute-scoped state and listeners.

## Boundaries

- Super Admin stays server-claim controlled and can never be created by an institute code.
- Institute Admin approval is same-institute only; it cannot create another Institute Admin membership.
- Teachers keep their existing permission model per active membership.
- Parent Connect remains restricted to approved parent–student links. A parent membership does not disclose any child data by itself.
- Mobile clients must not approve, activate, revoke, or alter another user’s membership directly.

## Migration

Current `users/{uid}.role` and `instituteId` fields remain the legacy login source until a trusted backfill creates matching active memberships. No legacy field is removed or made client-writable during the transition.
