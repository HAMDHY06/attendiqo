# Release and device-warning backlog

These items are recorded for review; this UI task does not change dependencies or deploy services.

1. Review the `mobile_scanner` Kotlin migration warning before a release dependency upgrade.
2. Treat ProviderInstaller, Phenotype, MotionEvent, PowerHalMgrImpl, ScrollIdentify, and enqueueInputEvent messages as device/system warnings unless accompanied by an app stack trace.
3. Review Firestore Rules warnings for unused helpers and variable naming during
   the next security-rule review. Several deliberately denied legacy audit-log
   create tests also reach the emulator's 1,000-expression evaluation ceiling;
   access remains denied and all tests pass, but those unrelated audit predicates
   should be simplified before a production Rules review.
4. Remove or reduce debug-only operation logs before release builds after support instrumentation is no longer required.
5. Firestore Emulator tests currently require Java on the developer machine PATH.
6. A transparent, launcher-safe foreground version of the approved Attendiqo mark is needed before replacing Android adaptive launcher assets without an unintended white square.
7. A reviewed redacted institute-public-profile projection is needed before a
   Teacher header can show a live institute name without reading the full
   institute document.
8. The Phase 7 review-only callable wrapper and its canonical writers are now
   self-contained and package-boundary tested. It still requires staging App
   Check/provider validation, Node 22 runtime validation, monitoring, event
   triggers, TTL policies, and scheduled reconciliation.
9. Live parent attendance remains unavailable until the trusted attendance
   backend supplies authoritative records and stable `YYYY-MM-DD` date keys.
10. The Functions dependency audit currently reports seven moderate transitive
    findings. Review upstream fixes without applying a forced breaking audit fix.
11. Local Functions Emulator testing falls back to host Node 24; production
    compatibility must be confirmed using the configured Node 22 runtime.
12. The current audit has seven moderate findings through
    `firebase-admin -> @google-cloud/storage -> gaxios/retry-request/teeny-request
    -> uuid@9`. Direct dependencies are current. npm offers only a forced
    downgrade to `firebase-admin@10.3.0`, so no breaking remediation was applied.
13. Projection transactions are explicitly callable today. Production still
    needs reviewed event triggers and scheduled reconciliation so source changes
    propagate without an administrator manually requesting synchronization.
14. Live attendance projection remains blocked on the trusted attendance
    source writer. The projection contract and correction behavior are tested
    only with trusted emulator-seeded attendance records.
15. Deploying the projection writers must backfill the protected
    `users/{parentUid}.parentLinkedStudentIds` discovery index before Connect
    can discover existing links. Parent clients cannot perform this backfill.
16. Real Connect notices remain unavailable. Strict request-time expiry Rules
    rejected the broad list query in emulator testing; implement a reviewed
    parent-specific notice feed or authenticated read callable instead of
    weakening Rules.
17. Projection-backed Connect screens are implemented, but real-device data
    remains unavailable until Functions, Rules, indexes, App Check, source
    synchronization, and projection backfill receive human review and staging
    deployment.
# Phase 7 staging blockers

- Execute the reviewed Node 22 test suite (current workstation is Node 24 only).
- Configure and validate Android App Check in staging with non-committed debug tokens.
- Review migration dry-run mismatch aggregates, then execute only against a staging project.
- Deploy and smoke-test reviewed Functions/Rules/indexes in staging before connecting the live notice callable.
- Implement event-driven projection triggers and scheduled reconciliation only after their retry, loop-prevention and monitoring design receives review.
- Resolve or formally accept each `npm audit` transitive moderate finding.
