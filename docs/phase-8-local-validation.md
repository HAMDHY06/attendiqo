# Phase 8 local notification-device validation

Status: **Implemented locally**, **Review-only**, **Undeployed**.

The self-service device callables require authenticated matching UID, active
trusted profile, active institute for institute-scoped roles, App Check and a
bounded payload. Devices are callable-only: client Firestore reads/writes are
denied. Tokens are hashed for identity; the raw token is retained only in the
backend-protected field and is neither returned nor logged. Refresh atomically
deactivates the old device and writes the new one. Hashed rate-limit buckets
are server controlled.

Node 22, staging App Check and real FCM device validation remain blocked and
no delivery claim is made.

Local Firestore-Emulator integration validation: 17 tests passed, including
all active roles, device registration/reuse, multiple devices, atomic refresh,
deactivation, permission update, Auth/App Check rejection and malformed input.

The callable-only preference writer has local unit coverage. Direct preference
reads and writes are denied in the Rules Emulator; creation and updates happen
only through the review-only callable boundary.

Latest local validation (Node 24 fallback):

- Shared Flutter analyzer: no issues; 63 tests passed.
- Attendiqo analyzer: no issues; 52 tests passed.
- Attendiqo Connect analyzer: no issues; 22 tests passed.
- Functions unit/package suite: 24 tests passed.
- Firestore Rules Emulator: 58 tests passed.
- JavaScript syntax check: passed.

The Flutter runtime work is still locally testable only through the shared
route/permission contracts. Real Android background delivery, token transport,
App Check and FCM display remain staging/device blocked.
