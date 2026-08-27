# Attendiqo SMS Worker (review-only, undeployed)

This is the Firebase Spark-compatible SMS trust boundary. It uses Firebase ID
tokens in `Authorization: Bearer` and validates them for project
`attendiqo-system`; it does not use Firebase Functions, Firebase Secret Manager,
or Cloudflare Access credentials from Flutter.

Only these Cloudflare Worker secrets are required after human review:

- `TEXTLK_API_TOKEN`
- `TEXTLK_SENDER_ID`

Never put either value in `wrangler.jsonc`, Dart defines, a test, an audit entry,
or a log. No command in this repository deploys this Worker automatically.

The Durable Object `SMS_LEDGER` persists a per-institute aggregate quota and
hashed de-duplication keys. It never stores a phone number or message body.
The default monthly limit is 500 and SMS is disabled until an authorized setting
is written through the Worker. Real provider delivery and Worker deployment are
blocked pending human review, legal consent wording, and sandbox validation.

Local checks (no provider traffic):

```powershell
Set-Location C:\Users\farha\Desktop\Attendiqo\attendiqo-sms-api
npm.cmd run cf-typegen
npx.cmd tsc --noEmit
npm.cmd test -- --run
```

The future human-reviewed deployment command is deliberately documented only
after full worker authorization and quota integration tests pass.
