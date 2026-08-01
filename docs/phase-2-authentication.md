# Phase 2 Authentication and Profiles

Both Flutter apps use Firebase Authentication email/password sessions and load `users/{uid}` from Cloud Firestore through a repository adapter. A shared `AuthenticationController` listens to authentication-state changes and applies a typed role/audience policy before selecting a screen.

## Profile document

```text
uid: string
email: string
displayName: string
role: superAdmin | instituteAdmin | teacher | parent
instituteId: string | null
active: boolean
mustChangePassword: boolean
createdAt: timestamp
createdBy: string
updatedAt: timestamp
lastLoginAt: timestamp | null
```

Super Admin must have `instituteId: null`. Institute Admin and teacher profiles require an institute ID. Parents do not require one. No password is stored in Firestore.

## Password-change limitation

Firebase Authentication password update succeeds before the client clears `mustChangePassword`. Firestore rules permit only `true -> false` plus timestamp updates and forbid role, institute, active, and identity changes. Before production hardening, move the flag-clearing operation to a reviewed callable backend if stronger cross-service atomic verification is required.

## Rule review and emulator command

From `Firebase/tests`, install reviewed dependencies, then from `Firebase/` run:

```text
firebase emulators:exec --only firestore "npm --prefix tests test" --project attendiqo-system --config firebase.json
```

Only after the emulator tests pass and a human reviews the diff should rules be deployed:

```text
firebase deploy --only firestore:rules --project attendiqo-system --config Firebase/firebase.json
```

Do not deploy automatically from a development task.
