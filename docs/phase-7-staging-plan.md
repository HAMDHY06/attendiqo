# Phase 7 staging plan (review required)

Phase 7 is **not production-ready**. No command in this document has been run against a Firebase project.

## Preconditions

1. Review the Git diff and run the complete local validation suite under Node 22.
2. Confirm the target project is the non-production staging project, then verify its billing, owners and Firebase project ID in the console.
3. Configure Android App Check: use the debug provider only for local development; use Play Integrity (or an approved provider) for staging/release. Debug tokens are local secrets and must never be committed.
4. Run the link-discovery migration dry run with external Admin credentials:

```powershell
node Firebase/functions/tools/backfill_parent_link_discovery.mjs --dry-run --run-id=phase7-staging-001
```

5. Review aggregate mismatch counts. Correct malformed or cross-institute source links before execution.

## Human-reviewed staging sequence

```powershell
firebase use <staging-project-id>
firebase deploy --only functions --config Firebase/firebase.json
firebase deploy --only firestore:rules,firestore:indexes --config Firebase/firebase.json
node Firebase/functions/tools/backfill_parent_link_discovery.mjs --execute --run-id=phase7-staging-001
```

After every bounded execution, read the protected checkpoint document, run the matching dry run, then perform an Android smoke test with a valid App Check token and a revoked-link case. Monitor callable failures, App Check rejections, projection mismatches and Firestore volume before widening access.

## Callable trust boundary

Administrative projection calls verify Firebase Auth token UID matching, active same-institute Institute Admin status, active source records, App Check and a hashed-actor rate-limit bucket. The parent notice reader separately verifies an active parent and derives every target scope server-side. It accepts neither a parent UID nor target IDs from the mobile client.

`listApplicableParentNotices` is intentionally callable rather than a broad Firestore read. It filters publication time, expiry, active state and target scope against trusted server time, returns at most 50 parent-safe notices, and records safe aggregate callable audits.

## Node and App Check validation

The deployment engine remains Node 22. This workstation uses Node 24, which is an emulator-only fallback; staging requires a Node 22 run in CI, a managed runner or a verified local Node 22 installation. Test missing App Check, invalid App Check, valid App Check, UID mismatch, inactive parent and revoked link before staging promotion.
