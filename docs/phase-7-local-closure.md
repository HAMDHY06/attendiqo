# Phase 7 local closure — 2026-08-03

## Honest local inventory

| Component | Status |
| --- | --- |
| Parent authentication, links, discovery index, safe student/class/attendance/institute projections | Implemented locally; locally tested where covered by existing suites |
| Connect repository, selected-child controller, Home/Children/Attendance/Profile UI | Implemented locally; locally tested |
| Notice callable, trigger foundation, reconciliation and migration utility | Review-only; undeployed |
| Connect real notice feed | Deferred until the review-only callable has staging validation; unavailable state remains correct |
| Trusted production attendance source | Production-backend blocked |
| Node 22/App Check/migration/reconciliation/monitoring/rollback/device validation | Staging-blocked |
| TTL policy and production alerts | Deferred; documentation only |

## Security closure

Rules remain restrictive: mobile parents cannot write trusted links, projections,
discovery indexes, notices, attendance or backend state. Raw students, classes,
institutes, teachers, attendance sources, audits and QR data remain denied.
Parent scope comes from deterministic active links, inactive parents/links and
suspended institutes are denied, and cross-institute access is denied. The
notice callable derives scope server-side, requires UID verification and has
App Check enforcement configured. No secret or debug token is committed and no
deployment command has been executed.

## Node 22 handoff

Install Node **22 LTS** using nvm-windows, a verified Node installer, CI, or a
Node 22 container. Confirm `node --version` is `v22.x`, then run from the
repository root: Functions package tests, callable integration/protocol tests,
backend tests, syntax checks and `npm audit`. Record Node/npm versions, command,
test total, result and any Node 22-vs-24 difference. Until that run passes,
Node 22 validation is **Staging-blocked**.

## App Check handoff

Use a separate staging Firebase project. Configure a local Android debug
provider without committing its token, then configure Play Integrity (or an
approved provider) for staging. Validate missing/invalid/valid tokens, UID
mismatch, inactive parent, revoked link and notice callable. Roll back by
returning to monitored App Check only after security review. This is
**Staging-blocked** and has not been performed.

## Ordered staging handoff

1. Verify staging project, account, Git commit and diff.
2. Install Node 22 and run all backend suites.
3. Configure App Check and verify token cases.
4. Run discovery migration dry-run and review aggregate mismatches.
5. Human-review deployment of Functions, Rules and indexes.
6. Run bounded backfill and reconciliation dry-run, then approved repairs.
7. Verify projections, notice callable, revocation behavior and Connect UI.
8. Verify attendance remains unavailable unless its trusted backend is deployed.
9. Check monitoring, perform rollback drill, then physical-device testing.

No staging action is authorized or executed by this document.

## Classification

- Foundation: **partially complete**
- Implementation complete: **no**
- Staging-ready: **no**
- Production-ready: **no**

## Deferred external blockers

Node 22, App Check staging, staging deployment, migration/reconciliation
execution, monitoring, rollback drill, physical-device testing and the trusted
attendance backend are explicitly deferred until appropriate staging access and
human review are available. They are not completed locally.
