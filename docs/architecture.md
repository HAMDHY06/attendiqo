# Foundation Architecture

Each Flutter app owns its UI, navigation, Firebase adapters, and feature composition. The shared Dart package owns immutable typed domain models, enums, validators, repository/service contracts, result/failure types, collection constants, date utilities, and provider-free mocks.

Dependencies point inward: presentation uses domain contracts; Firebase and future Notify.lk adapters implement those contracts. Constructor injection keeps business logic testable. No global mutable service locator is introduced.

## Attendance and delivery boundary

The trusted attendance repository saves first. Push and optional SMS are separate backend work with idempotency based on the attendance event ID. Delivery failure is logged and retried without rolling back attendance.

## Continuous scanner state

Future states are idle, validating, accepted, rejected, and recoverable error. After a valid scan, show the latest student result below the camera and return to scanning after a per-token cooldown. No per-student confirmation action is allowed. Validate opaque token, active student, institute, selected class, event order, duplicate event, and server timestamp.

## Security boundaries

Firestore starts deny-all. Future rules must verify server-managed roles and institute membership. Teachers query assigned classes only; parents query approved linked students only. Sensitive notification sending and QR state changes belong in a trusted backend.
