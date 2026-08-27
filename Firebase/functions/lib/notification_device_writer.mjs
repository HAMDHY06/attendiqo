import { FieldValue } from 'firebase-admin/firestore';
import { SafeCallableError } from './callable_core.mjs';
import { tokenHash, tokenIdFor } from './self_service_callable_core.mjs';

const packages = new Set(['com.hamdhytech.attendiqo', 'com.hamdhytech.attendiqo.connect']);
const statuses = new Set(['unknown', 'granted', 'denied', 'permanentlyDenied']);
const fail = () => { throw new SafeCallableError('invalid-argument', 'The request contains invalid information.'); };
const exact = (data, keys) => Object.keys(data).every((key) => keys.has(key)) && [...keys].every((key) => key in data);
const validText = (value, min, max) => typeof value === 'string' && value.length >= min && value.length <= max;
export const validateDeviceRegistration = (data) => {
  const keys = new Set(['token', 'appPackage', 'platform', 'appVersion', 'deviceHash', 'permissionStatus']);
  if (!exact(data, keys) || !validText(data.token, 32, 4096) || !packages.has(data.appPackage)
      || data.platform !== 'android' || !validText(data.appVersion, 1, 80)
      || !validText(data.deviceHash, 16, 128) || !statuses.has(data.permissionStatus)) fail();
  return data;
};
export async function registerDevice({ firestore, uid, data }) {
  const { oldTokenId: _oldTokenId, ...registration } = data;
  const input = validateDeviceRegistration(registration);
  const tokenId = tokenIdFor(input); const ref = firestore.collection('notification_devices').doc(uid).collection('tokens').doc(tokenId);
  await ref.set({ uid, tokenId, protectedToken: input.token, tokenHash: tokenHash(input.token), appPackage: input.appPackage,
    platform: 'android', appVersion: input.appVersion, deviceHash: input.deviceHash, active: true,
    permissionStatus: input.permissionStatus, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    lastSeenAt: FieldValue.serverTimestamp(), invalidatedAt: null, sourceVersion: 1 }, { merge: true });
  return { registered: true, tokenId, active: true, appPackage: input.appPackage, platform: 'android', permissionStatus: input.permissionStatus };
}
export async function deactivateDevice({ firestore, uid, data }) {
  if (!data || !exact(data, new Set(['tokenId'])) || !validText(data.tokenId, 16, 80)) fail();
  const ref = firestore.collection('notification_devices').doc(uid).collection('tokens').doc(data.tokenId);
  const existing = await ref.get();
  if (!existing.exists || existing.data()?.uid !== uid) throw new SafeCallableError('not-found', 'The requested record is unavailable.');
  await ref.update({ active: false, invalidatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  return { deactivated: true };
}
export async function updatePermission({ firestore, uid, data }) {
  if (!data || !exact(data, new Set(['tokenId', 'permissionStatus'])) || !validText(data.tokenId, 16, 80) || !statuses.has(data.permissionStatus)) fail();
  const ref = firestore.collection('notification_devices').doc(uid).collection('tokens').doc(data.tokenId);
  const existing = await ref.get();
  if (!existing.exists || existing.data()?.uid !== uid) throw new SafeCallableError('not-found', 'The requested record is unavailable.');
  await ref.update({ permissionStatus: data.permissionStatus, updatedAt: FieldValue.serverTimestamp(), lastSeenAt: FieldValue.serverTimestamp() });
  return { updated: true, permissionStatus: data.permissionStatus };
}
export async function refreshDevice({ firestore, uid, data }) {
  if (!data || !exact(data, new Set(['oldTokenId', 'token', 'appPackage', 'platform', 'appVersion', 'deviceHash', 'permissionStatus'])) || !validText(data.oldTokenId, 16, 80)) fail();
  const { oldTokenId: _oldTokenId, ...registration } = data;
  const input = validateDeviceRegistration(registration);
  const oldRef = firestore.collection('notification_devices').doc(uid).collection('tokens').doc(data.oldTokenId);
  const tokenId = tokenIdFor(input); const nextRef = firestore.collection('notification_devices').doc(uid).collection('tokens').doc(tokenId);
  await firestore.runTransaction(async (transaction) => {
    const old = await transaction.get(oldRef);
    if (!old.exists || old.data()?.uid !== uid) throw new SafeCallableError('not-found', 'The requested record is unavailable.');
    transaction.set(oldRef, { active: false, invalidatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    transaction.set(nextRef, { uid, tokenId, protectedToken: input.token, tokenHash: tokenHash(input.token), appPackage: input.appPackage, platform: 'android', appVersion: input.appVersion, deviceHash: input.deviceHash, active: true, permissionStatus: input.permissionStatus, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), lastSeenAt: FieldValue.serverTimestamp(), invalidatedAt: null, sourceVersion: 1 }, { merge: true });
  });
  return { refreshed: true, tokenId, active: true, appPackage: input.appPackage, platform: 'android', permissionStatus: input.permissionStatus };
}
