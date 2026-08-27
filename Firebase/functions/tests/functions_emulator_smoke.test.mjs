import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

const callableUrl = 'http://127.0.0.1:5001/attendiqo-system/us-central1/createOrReactivateParentLink';
const authUrl = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-key';
const payload = JSON.stringify({
  data: {
    idempotencyKey: 'phase7-emulator-smoke-request',
    parentUid: 'parent-a', studentId: 'student-a', relationship: 'parent',
  },
});

const invoke = async (headers = {}) => {
  const response = await fetch(callableUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: payload,
  });
  return { status: response.status, body: await response.json() };
};

test('actual callable protocol rejects unauthenticated and invalid tokens', async () => {
  const unauthenticated = await invoke();
  assert.notEqual(unauthenticated.status, 200);
  assert.equal(JSON.stringify(unauthenticated.body).includes('student-a'), false);

  const invalid = await invoke({ authorization: 'Bearer invalid-token' });
  assert.notEqual(invalid.status, 200);
  assert.equal(JSON.stringify(invalid.body).includes('invalid-token'), false);
});

test('authenticated callable request without App Check is rejected', async () => {
  const authResponse = await fetch(authUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email: `phase7-${Date.now()}@example.test`,
      password: `A1!a${randomBytes(12).toString('base64url')}`,
      returnSecureToken: true,
    }),
  });
  const authBody = await authResponse.json();
  assert.ok(authBody.idToken);
  const result = await invoke({ authorization: `Bearer ${authBody.idToken}` });
  assert.notEqual(result.status, 200);
  const serialized = JSON.stringify(result.body);
  assert.equal(serialized.includes(authBody.idToken), false);
  assert.equal(serialized.includes('student-a'), false);
});
