# Attendiqo role and Teacher permission matrix

Status: reviewed during the Phase 5–6 stabilization pass. This document does not start Phase 7 and does not authorize deployment.

## Institute Admin policy

`InstituteAdminCapabilities.fullWithinInstitute` is the typed application policy. An active Institute Admin receives every institute-management capability without Teacher-style switches, but only while their profile and institute are active and the target `instituteId` matches their immutable profile assignment.

The policy covers class lifecycle and primary-Teacher assignment, student lifecycle and enrolment, schedule changes and overlap approval, QR/attendance/report requests, parent-contact viewing, Teacher administration, password recovery, and institute audit viewing. Reservation documents, raw QR tokens, attendance transactions, and privileged account creation remain protected transactions or trusted-backend operations.

## Teacher permissions

| Permission | Visible feature | Allowed action | Controller check | Repository/service check | Rules check | Trusted backend check | Tests |
|---|---|---|---|---|---|---|---|
| `canCreateClasses` | Create Class button and dashboard action | Create in own institute; creator becomes sole primary Teacher | `AcademicAuthorization.canCreateClass` | Repository rejects wrong institute/assignment/creator | `validTeacherClassCreate`; class-code reservation transaction | Not required for one safe primary assignment | Shared authorization, controller auto-assignment, widget visibility, emulator allow/deny |
| `canEditClasses` | Edit and schedule actions on assigned classes | Edit assigned, non-archived class fields | `canEditClass` and `canManageScheduleChange` | Repository reloads current class and preserves assignment/status for Teacher | `validTeacherClassUpdate`; assignment/status immutable; archived denied | Multiple-Teacher assignment remains trusted-only | Shared assignment tests, controller denial, emulator edit/assignment/status/archive tests |
| `canAddStudents` | Students destination/quick action with **Not configured** state | Request creation only after trusted assigned-student service exists | Direct controller creation returns safe backend-unavailable state | Direct repository creation is Institute Admin/Super Admin only | Teacher writes to `students` and `student_numbers` denied | Must validate assigned class, uniqueness, redacted response and audit | Shared trusted-boundary and widget visibility tests |
| `canEditStudents` | Students destination with **Not configured** state | Edit only an assigned-class student through future trusted service | Direct controller editing denied for Teacher | Direct repository editing denied for Teacher | Full student document writes denied to Teacher | Must protect institute, student number, QR and audit fields | Shared trusted-boundary and navigation tests |
| `canGenerateQrCodes` | QR action only when an eligible assigned student is available | Request QR regeneration/enable/disable for assigned-class students | `AttendanceAuthorization.canGenerateStudentQr` | QR service repeats assignment and permission checks | `qr_tokens` remains fully denied to mobile clients | Required; validates class enrolment and never logs raw token | Shared QR assignment tests and controller boundary tests |
| `canTakeAttendance` | Attendance destination and Start Attendance action | Start/use session for assigned active class | `canTakeClassAttendance` | Attendance service repeats assignment, permission, institute and class checks | Attendance collections remain denied to mobile clients | Required; verifies claims, active profile/institute, assignment and session | Shared service tests, widget visibility, backend Node tests, emulator boundary tests |
| `canCorrectAttendance` | Correction/manual controls for assigned class | Correct assigned-class record with mandatory reason | `canCorrectClassAttendance` including reason validation | Attendance service preserves original record history and appends correction | Corrections remain denied to mobile clients | Required; auditable transaction and immutable original values | Shared reason/assignment tests and controller tests |
| `canExportReports` | Reports destination and export controls | Export only currently loaded assigned-class records | `canExportClassReport` | Export layer receives scoped records only | Production historical records are not opened directly | Required for historical/date-range reports | Shared authorization and widget visibility tests |
| `canViewParentContacts` | No full-profile screen; future redacted assigned-student projection | View contacts only for assigned students when projection exists | `canViewParentContacts(... assignedStudentProjection: true)` | Full student list is not queried for Teacher | Teacher reads of full `students` documents remain denied | Required; omit contact fields entirely when false | Shared privacy-boundary tests and emulator denial tests |
| `canSendManualNotifications` | **Not configured** card only | No sending action in this task | `canSendManualNotification` requires backend availability | No production notification repository is called | No notification collection was opened | Required before any action becomes enabled | Shared unavailable-state authorization and widget tests |

## Super Admin verification

Cross-institute Firestore access continues to require `request.auth.token.superAdmin == true` plus an active Super Admin profile. The authentication repository rejects a Firestore `role: superAdmin` profile when the ID token does not contain the verified claim. A writable profile field alone cannot grant cross-institute access.

## Review boundary

The Flutter UI may explain that a permission is enabled while its trusted backend is not configured. It must never simulate success, open Firestore Rules broadly, or load parent-contact fields merely to hide them later.
