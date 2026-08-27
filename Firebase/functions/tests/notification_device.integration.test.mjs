import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { createSelfServiceCallableBoundary, consumeSelfServiceRateLimit } from '../lib/self_service_callable_core.mjs';
import * as devices from '../lib/notification_device_writer.mjs';

let app; let db; let boundary;
const token = 't'.repeat(64);
const payload = (overrides = {}) => ({ token, appPackage: 'com.hamdhytech.attendiqo.connect', platform: 'android', appVersion: '1.0.0', deviceHash: 'd'.repeat(32), permissionStatus: 'granted', ...overrides });
const request = (uid, data, appCheck = true) => ({ auth: uid ? { uid } : null, app: appCheck ? { appId: 'emulator' } : null, data });
const call = (uid, data, action = 'register') => boundary({ request: request(uid, data), handler: async context => {
  await consumeSelfServiceRateLimit({ firestore: db, uid: context.uid, operation: action, nowMs: 1000, limit: 30 });
  if (action === 'register') return devices.registerDevice({ firestore: db, ...context });
  if (action === 'refresh') return devices.refreshDevice({ firestore: db, ...context });
  if (action === 'deactivate') return devices.deactivateDevice({ firestore: db, ...context });
  return devices.updatePermission({ firestore: db, ...context });
} });
before(async () => { assert.ok(process.env.FIRESTORE_EMULATOR_HOST); app = initializeApp({ projectId: 'attendiqo-system' }, `device-${Date.now()}`); db = getFirestore(app); boundary = createSelfServiceCallableBoundary({ firestore: db, verifyIdToken: async value => ({ uid: value.auth.uid }) }); });
beforeEach(async () => { for (const item of await db.listCollections()) await db.recursiveDelete(item); await Promise.all(['parent','teacher','admin','super'].map((role, index) => db.collection('users').doc(role).set({ uid: role, role: index === 0 ? 'parent' : index === 1 ? 'teacher' : index === 2 ? 'instituteAdmin' : 'superAdmin', active: true, instituteId: index === 0 || index === 3 ? null : 'inst' }))); await db.collection('institutes').doc('inst').set({ active: true, status: 'active' }); });
after(async () => { await deleteApp(app); });
test('all active roles register idempotently and support multiple devices', { concurrency: false }, async () => { for (const uid of ['parent','teacher','admin','super']) assert.equal((await call(uid, payload())).registered, true); await call('parent', payload()); await call('parent', payload({ token: 'u'.repeat(64), deviceHash: 'e'.repeat(32) })); assert.equal((await db.collection('notification_devices').doc('parent').collection('tokens').get()).size, 2); });
test('refresh, deactivate and permission update are safe and scoped', { concurrency: false }, async () => { await call('parent', payload()); const old = (await db.collection('notification_devices').doc('parent').collection('tokens').get()).docs[0].id; const fresh = await call('parent', { oldTokenId: old, ...payload({ token: 'v'.repeat(64) }) }, 'refresh'); assert.equal(fresh.refreshed, true); assert.equal((await db.collection('notification_devices').doc('parent').collection('tokens').doc(old).get()).data().active, false); const next = (await db.collection('notification_devices').doc('parent').collection('tokens').get()).docs.find(x => x.id !== old).id; assert.equal((await call('parent', { tokenId: next }, 'deactivate')).deactivated, true); assert.equal((await call('parent', { tokenId: next, permissionStatus: 'denied' }, 'permission')).permissionStatus, 'denied'); });
test('auth, app check and malformed payloads reject without returning token', { concurrency: false }, async () => { for (const value of [request(null, payload()), request('parent', payload(), false)]) await assert.rejects(boundary({ request: value, handler: async () => ({}) }), error => !error.message.includes(token)); await assert.rejects(call('parent', { ...payload(), uid: 'other' }), error => error.code === 'invalid-argument' && !error.message.includes(token)); });
