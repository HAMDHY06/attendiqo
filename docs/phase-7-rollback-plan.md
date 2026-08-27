# Phase 7 rollback plan (review required)

No deployment has been made. If staging deployment is approved, retain the exact reviewed Git commit and deploy artifacts.

| Area | Rollback | Data impact |
| --- | --- | --- |
| Functions | Redeploy the prior reviewed Functions revision or disable affected callable traffic. | Does not reverse prior trusted writes. |
| Rules | Redeploy the prior reviewed rules file. | May temporarily reduce parent read access; never use open rules. |
| Indexes | Disable unused indexes only after affected queries are removed. | Index removal is asynchronous and does not delete documents. |
| Link discovery | Re-run migration from authoritative active links, or apply a compensating trusted write. | `parent_student_links` remains source of truth. |
| Projection triggers | Disable the trigger/function and use bounded reconciliation after correction. | Projections may be stale; source records remain authoritative. |
| Notice callable | Disable the callable; Connect must show its explicit unavailable state. | No source notices are deleted. |
| App Check | Return to monitored mode only after security review; do not broadly bypass verification. | No data migration is involved. |

Protected audit history, attendance source data and legal-retention records must never be deleted as a rollback shortcut.
