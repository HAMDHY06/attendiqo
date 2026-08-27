import test from 'node:test';
import assert from 'node:assert/strict';
import { createSelfServiceCallableBoundary } from '../lib/self_service_callable_core.mjs';

const profile = { exists: true, data: () => ({ uid: 'parent-a', role: 'parent', active: true }) };
const firestore = { collection: () => ({ doc: () => ({ get: async () => profile }) }) };
const request = ({ uid = 'parent-a', app = true, data = {} } = {}) => ({ auth: uid ? { uid } : null, app: app ? { appId: 'test' } : null, data });
const boundary = createSelfServiceCallableBoundary({ firestore, verifyIdToken: async value => ({ uid: value.auth.uid }) });
test('self-service boundary accepts only its verified active user context', async () => {
  const value = await boundary({ request: request({ data: { value: true } }), handler: async context => ({ uid: context.uid, role: context.role }) });
  assert.deepEqual(value, { uid: 'parent-a', role: 'parent' });
});
test('self-service boundary rejects missing auth, App Check and oversized payload safely', async () => {
  for (const value of [request({ uid: null }), request({ app: false }), request({ data: { value: 'x'.repeat(9000) } })]) {
    await assert.rejects(boundary({ request: value, handler: async () => ({}) }), error =>
      ['unauthenticated', 'failed-precondition', 'invalid-argument'].includes(error.code) && !error.message.includes('parent-a'));
  }
});
