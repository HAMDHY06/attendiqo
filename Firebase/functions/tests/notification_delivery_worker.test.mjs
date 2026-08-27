import test from 'node:test';
import assert from 'node:assert/strict';
import { processNotificationOutbox } from '../lib/notification_delivery_worker.mjs';

const item = { notificationId: 'notice-a', recipientUid: 'user-a', title: 'safe', body: 'safe', route: 'home', attempts: 0 };
const run = async ({ send = async () => ({ messageId: 'provider-id' }), dryRun = false } = {}) => {
  const records = []; const updates = []; const invalidated = []; const logs = [];
  const result = await processNotificationOutbox({ listPending: async () => [item], claim: async () => true, listActiveDevices: async () => [{ tokenHash: 'hash-a', protectedToken: 'raw-token-never-logged' }], send, record: async value => records.push(value), updateOutbox: async (...value) => updates.push(value), deactivateToken: async value => invalidated.push(value), logger: value => logs.push(value), dryRun });
  return { result, records, updates, invalidated, logs };
};
test('worker delivers a bounded safe batch without logging payloads or tokens', async () => {
  const value = await run(); assert.equal(value.result.sent, 1); assert.equal(value.records[0].status, 'sent'); assert.equal(JSON.stringify(value.logs).includes('raw-token'), false);
});
test('worker retries transient failures and invalidates invalid tokens', async () => {
  const transient = await run({ send: async () => { throw { code: 'unavailable' }; } }); assert.equal(transient.updates[0][1].status, 'retry');
  const invalid = await run({ send: async () => { throw { code: 'messaging/registration-token-not-registered' }; } }); assert.deepEqual(invalid.invalidated, ['hash-a']);
});
test('dry run causes no delivery writes', async () => {
  const value = await run({ dryRun: true }); assert.equal(value.records.length, 0); assert.equal(value.updates.length, 0);
});
