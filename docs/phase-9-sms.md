# Phase 9 SMS foundation

Status: **Implemented locally**, **Review-only**, **Undeployed**, and
**provider-blocked**.

## Spark-compatible Cloudflare Worker boundary

The production-design SMS path is `attendiqo-sms-api`, not Firebase Functions.
It is intentionally undeployed. Flutter authenticates to the Worker with the
current Firebase ID token in `Authorization: Bearer`; it never sends a Cloudflare
Access service token, a parent phone number, an institute scope for an Institute
Admin, a role, or free-form SMS text.

The Worker validates the Firebase ID token for `attendiqo-system` (issuer,
audience, expiry, signature and subject), uses the same bearer token for
Rules-enforced reads of the caller profile and authoritative source records, and
checks active role and active institute state. Only an active Institute Admin
for the student's institute or a verified Super Admin may request a supported
manual event. Attendance events deliberately return an unavailable state until
the trusted attendance source is deployed; no client may manufacture an
attendance SMS.

`TEXTLK_API_TOKEN` and `TEXTLK_SENDER_ID` are Worker secrets only. They are not
Flutter configuration, Firestore documents, Functions secrets, log values, or
test fixtures. `protectedPhone` is not written to Firestore in this design;
the Worker obtains the parent mobile only after authorization, normalizes it to
Sri Lankan E.164 form, and passes it directly to the provider. The Durable
Object ledger stores only hashed de-duplication identifiers and aggregate quota
state, never a phone number or message body.

Each institute has a default disabled configuration and a monthly limit of 500.
The ledger reserves capacity before provider submission, then atomically settles
the reservation: only a provider-accepted request increments `used`; failed or
retryable requests release the reservation. The response contains only a safe
status. Current supported manual events are `importantNotice`,
`emergencyNotice`, and `monthlyPaymentReminder`; templates are bounded,
server-rendered, and allow only `{{student}}`, `{{institute}}`, and `{{date}}`.

Parent SMS consent is stored as minimal `student_sms_consents/{studentId}` data
(`studentId`, `instituteId`, `granted`, `updatedAt`). A linked active parent may
create or update only their linked child's consent. The Worker fails closed if
consent is missing or withdrawn. This is a technical consent flag only; the
wording in `parent-consent-draft.md` remains subject to human legal review.

The `SmsLedger` Durable Object binding and its migration are configuration only
until a human deploys the Worker. Do not run a deploy command until Worker JWT,
authorization, quota, provider sandbox, and consent tests have passed.

## Local validation — 2026-08-06

- Worker TypeScript: passed.
- Worker unit/integration tests: **9 passed**. These use an ephemeral signed
  Firebase JWT fixture, mocked Google JWKS/Firestore/Text.lk endpoints, and a
  local quota-ledger contract. They cover cryptographic token acceptance and
  rejection, active same-institute authorization, consent, duplicate
  suppression, reservation settlement, and provider retry release.
- Firestore Rules Emulator: **60 passed**, including linked-parent consent and
  no-broadened-access tests.
- Shared Flutter: analyzer clean; **63 passed**.
- Attendiqo: analyzer clean; **52 passed**.
- Attendiqo Connect: analyzer clean; **22 passed**.

No Worker was deployed, no Text.lk request was made, and no real SMS was sent.

## Human-reviewed deployment command (do not run automatically)

After a human has reviewed the diff, created the Durable Object binding in the
Cloudflare account, and supplied secrets interactively, run:

```powershell
Set-Location C:\Users\farha\Desktop\Attendiqo\attendiqo-sms-api
npm.cmd run cf-typegen
npx.cmd wrangler secret put TEXTLK_API_TOKEN
npx.cmd wrangler secret put TEXTLK_SENDER_ID
npx.cmd wrangler deploy
```

The secret prompts must be completed in the terminal; never paste the values
into source code, an issue, a command history, or Dart defines.

## One approved test-SMS validation

1. Obtain explicit SMS consent from one linked parent using the legally
   approved wording; record only the minimal consent flag.
2. In the Worker settings for that institute, enable SMS with a limit of `1`
   and allow only `importantNotice`.
3. Use an active same-institute Institute Admin account and a real Firebase ID
   token to invoke `/v1/send` for that consented student's ID with the manual
   event and a new source-event key. Do not include a phone number or message.
4. Confirm exactly one Text.lk provider attempt and a `sent` status; confirm
   Worker usage moves from `0/1` to `1/0` reserved.
5. Repeat the exact request and confirm `duplicate`, no second provider call,
   and unchanged usage. Disable SMS again after the test.

Attendance event types remain deliberately unavailable until a trusted
attendance backend exists. Institute Admin account creation remains blocked:
Firebase Spark plus a Worker without a privileged identity credential cannot
securely create Firebase Auth users or claims.

The local foundation normalizes Sri Lankan mobile numbers to E.164 and hashes
them for identity. Full numbers must remain in trusted backend-only fields and
must never be logged, audited or returned. `MockSmsProvider` is the only
provider implemented; no provider credentials, delivery worker or real SMS
transmission exists. A real provider requires human-approved secret
management, legal/consent review and physical-device validation.

The local review-only SMS outbox is server-only and idempotent. It stores an
E.164 number only in the protected backend field, stores its hash for identity,
and rejects sensitive template data. No client Rules are opened and it does
not call a provider.

Firestore Rules explicitly deny all mobile access to SMS outbox, delivery and
rate-limit collections.

A bounded mock-only delivery worker exists for local verification. It supports
dry runs and aggregate-only metrics but is not scheduled and cannot send SMS.
