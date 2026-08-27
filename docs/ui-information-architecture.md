# Attendiqo main-app information architecture

Status: UI restructuring in progress. This document does not change Firestore access, trusted-backend requirements, or product phases.

## Shared shell

`AttendiqoAppShell` is the only top-level role-aware navigation container. It retains tab state with an `IndexedStack`, uses `NavigationBar` on phones and `NavigationRail` at 840 logical pixels and above, and returns to Home when Android Back is pressed from another destination.

| Role | Destinations |
| --- | --- |
| Institute Admin | Home, People, Classes, Attendance, More |
| Teacher | Home, My Classes, Attendance, Students only when the assigned-student permission exists, Profile |
| Verified Super Admin | Overview, Institutes, Monitoring, Audit, More |

Primary destinations render directly inside the shell and reuse one controller
instance for the signed-in session. Create, edit, and detail flows remain
route-owned. Existing authorization checks remain the source of truth. The
shell creates the Home body first and lazily builds each later destination on
its first selection; visited destinations retain state through `IndexedStack`.

## Dashboard ordering

Institute Admin: header, primary actions, today status, two-column metrics, classes, action-required items, activity.

Teacher: header, current/next class, permitted quick actions, today classes, schedule changes, attendance, notices.

Super Admin: Control Centre header, platform metrics, institute health, attention items, activity, backend configuration.

## Privacy and availability

Teacher student pages never directly load full student documents. QR, attendance, corrections, notifications, and historical reports keep their existing trusted-backend-only states until their backend is deployed.

Teacher headers intentionally do not read full institute documents. Until a
reviewed `institute_public_profiles/{instituteId}` projection is designed,
they show a safe non-ID fallback rather than exposing institute contact or
configuration fields.
