# Phase 7 monitoring and retention readiness

All telemetry uses event names, severity, counts, latency and hashed actors only. It must never include names, email addresses, phone numbers, tokens, raw document IDs or request payloads.

| Signal | Suggested alert | Owner |
| --- | --- | --- |
| callable error/App Check rejection rate | >2% for 10 minutes | Platform owner |
| projection writer failures or stale-version rejections | any sustained increase | Backend owner |
| reconciliation/migration mismatches | non-zero after expected cleanup | Data owner |
| notice-feed failures/revoked-link attempts | >10 in 15 minutes | Security owner |
| function p95 latency and Firestore volume | exceeds staging baseline | Platform owner |

Recommended starting configuration: region close to Sri Lankan users after legal/latency review, `256MiB`, 30–60 second timeout, low concurrency first, per-actor callable limits, and dashboards split between staging and production.

## TTL/retention proposals (not enabled)

| Collection | Proposed retention | Cleanup | Impact |
| --- | --- | --- | --- |
| `backend_rate_limits` | 48 hours | Firestore TTL | rate-limit history only |
| `backend_idempotency` | 24 hours | Firestore TTL | retries older than window re-execute safely |
| `parent_link_migration_checkpoints` | 30 days | reviewed TTL/manual cleanup | resume data lost after completion only |
| temporary reconciliation state | 30 days | reviewed TTL | no authoritative data |
| expired notice projections | policy review | trusted cleanup | source notice retained as required |
| attendance projections/audit/revoked links | legal review required | no automatic deletion | operational/legal history |

TTL policies are deliberately not enabled in this repository.
