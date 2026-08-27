# Phase 8 notification foundation

Status: **Implemented locally**; **Locally tested**; **Review-only**;
**Undeployed**; not staging-ready.

The trusted design uses callable-only device registration, an Admin SDK outbox
writer and a bounded delivery worker. Proposed collections are
`notification_devices/{uid}/tokens/{tokenId}`, `notification_preferences/{uid}`,
`notification_outbox/{notificationId}` and `notification_deliveries/{deliveryId}`.
Raw FCM tokens must be stored only by trusted backend code, never in audits,
normal logs or mobile-readable documents.

The shared contracts define allowlisted event types, mandatory security alerts,
validated device-registration input and safe route allowlists. The local
backend now includes review-only callable device registration, refresh,
deactivation and permission-status operations. They run through a separate
active-user boundary, never Institute Admin management authority. Direct
Firestore access to device and preference records is denied.

Notification preferences are also callable-only, have role-specific defaults,
and reject unknown fields. `securityAlerts` remains enabled by the backend.
These foundations do not send FCM or expose notification UI in either app.

The canonical outbox writer is review-only and Admin-SDK-only. It creates a
bounded server-templated payload after an authoritative source action commits;
it rejects phone, email, token, QR, internal-path and private-note fields.
Its event hooks are not deployed and do not send notifications.

The delivery worker is also review-only and accepts injected trusted adapters
for local testing. It processes bounded batches, records only hashed delivery
identities, classifies retries, disables invalid tokens and supports dry-run.
It is not scheduled or exported, and it has not contacted FCM.

Both Android manifests now declare `POST_NOTIFICATIONS` for Android 13+.
Permission prompting, channels, foreground display and physical-device FCM
validation remain undeployed work; no notification icon was generated because
an approved monochrome icon has not been supplied.

A Firebase-free tap parser now accepts only a one-field, app-specific route.
It deliberately rejects child/class IDs and other payload data; each app must
still validate the signed-in user before navigating when Messaging is added.

The shared app contract now has a Firebase-less unavailable implementation so
tests and unsupported environments cannot attempt token registration.

Both apps now call only the reviewed self-service device callables for token
registration, rotation and sign-out deactivation. Tokens remain in the
Firebase Messaging/plugin boundary and are never returned by the callables.
Foreground, opened-app and terminated-app events are reduced to a one-field,
allowlisted route before they reach either shell. The shared coordinator then
rechecks the current active authenticated profile and app audience, deduplicates
the route, and selects only a generic shell destination. It never accepts a
student, class, institute, document ID or Firestore path from a payload.

Both apps now expose a local notification-permission settings screen. It
supports request permission, denied/permanently-denied guidance and opening
the Android app settings through `permission_handler`. It intentionally has no
notification inbox or preference toggles yet; security alerts remain backend
mandatory. Firebase-less runtimes receive the safe unavailable implementation.
No foreground system-notification display, Android notification channel/icon,
or real FCM delivery is claimed until staging and device validation occur.

The lifecycle is now coordinated with authentication: it cannot register a
device before an authenticated trusted session exists, and local sign-out
cancels listeners and attempts safe remote deactivation without blocking
sign-out when offline.

The shared `NotificationAuthorization` gate now rejects notification routes
without an active current session and rejects management-only routes for a
teacher. App shells must invoke this gate before navigation is connected.

Phase 7 external blockers remain deferred until staging exists; no Phase 7
claim is changed by this foundation work.
