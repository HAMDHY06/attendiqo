import test from 'node:test';
import assert from 'node:assert/strict';
import { notificationIdFor, writeNotificationOutbox } from '../lib/notification_outbox_writer.mjs';

const stored = new Map();
const firestore = { collection: name => ({ doc: id => ({ id, get: async () => name === 'users' ? ({ exists: true, data: () => ({ active: true, role: 'parent' }) }) : ({ exists: stored.has(id), data: () => stored.get(id) }), }) }), runTransaction: async fn => fn({ get: ref => ref.get(), create: (ref, value) => stored.set(ref.id, value) }) };
const request = { recipientUid: 'parent-a', recipientRole: 'parent', eventType: 'parentLinkCreated', route: 'children', safeData: { label: 'your institute' }, sourceVersion: 1, deduplicationKey: 'link-a' };
test('outbox IDs are deterministic and writes are idempotent', async () => {
  assert.equal(notificationIdFor(request), notificationIdFor(request));
  await writeNotificationOutbox({ firestore, ...request }); await writeNotificationOutbox({ firestore, ...request });
  assert.equal(stored.size, 1); assert.equal([...stored.values()][0].status, 'pending');
});
test('outbox rejects sensitive data and unsupported routes', async () => {
  await assert.rejects(writeNotificationOutbox({ firestore, ...request, safeData: { phone: 'private' } }));
  await assert.rejects(writeNotificationOutbox({ firestore, ...request, route: 'unsafe' }));
});
