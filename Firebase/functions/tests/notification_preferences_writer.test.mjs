import test from 'node:test';
import assert from 'node:assert/strict';
import { updatePreferences } from '../lib/notification_preferences_writer.mjs';

const writes = [];
const firestore = { collection: () => ({ doc: () => ({ get: async () => ({ exists: true, data: () => ({}) }), set: async value => writes.push(value) }) }) };
test('preferences reject unknown fields and preserve mandatory security alerts', async () => {
  await assert.rejects(updatePreferences({ firestore, uid: 'user', role: 'parent', data: { securityAlerts: false } }));
  const value = await updatePreferences({ firestore, uid: 'user', role: 'parent', data: { notices: false } });
  assert.equal(value.notices, false); assert.equal(value.securityAlerts, true);
});
