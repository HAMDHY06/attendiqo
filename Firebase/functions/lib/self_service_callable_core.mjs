// REVIEW-ONLY self-service boundary. It intentionally does not reuse the
// Institute Admin boundary: callers can act only on their authenticated UID.
import { createHash } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { SafeCallableError, mapCallableError } from './callable_core.mjs';

const roles = new Set(['superAdmin', 'instituteAdmin', 'teacher', 'parent']);
const hash = (value) => createHash('sha256').update(value).digest('hex');
const safe = (code) => new SafeCallableError(code, {
  unauthenticated: 'Authentication is required.', 'permission-denied': 'You are not authorized to perform this operation.',
  'failed-precondition': 'The requested operation cannot be completed in the current state.',
  'invalid-argument': 'The request contains invalid information.', 'resource-exhausted': 'Too many requests. Please try again later.',
}[code] ?? 'The operation could not be completed safely.');

export const createSelfServiceCallableBoundary = ({ firestore, verifyIdToken, maxBytes = 8192, now = () => Date.now() }) => async ({ request, handler }) => {
  const uid = request?.auth?.uid;
  try {
    if (!uid) throw safe('unauthenticated');
    let token; try { token = await verifyIdToken(request); } catch { throw safe('unauthenticated'); }
    if (token?.uid !== uid) throw safe('unauthenticated');
    if (!request?.app?.appId) throw safe('failed-precondition');
    const data = request.data;
    if (!data || typeof data !== 'object' || Array.isArray(data) || Buffer.byteLength(JSON.stringify(data)) > maxBytes) throw safe('invalid-argument');
    const profile = await firestore.collection('users').doc(uid).get();
    const value = profile.data();
    if (!profile.exists || value?.uid !== uid || value?.active !== true || !roles.has(value?.role)) throw safe('permission-denied');
    if ((value.role === 'instituteAdmin' || value.role === 'teacher')) {
      const institute = await firestore.collection('institutes').doc(value.instituteId ?? '').get();
      if (!institute.exists || institute.data()?.active !== true || institute.data()?.status !== 'active') throw safe('permission-denied');
    }
    return await handler({ uid, role: value.role, instituteId: value.instituteId ?? null, claims: token, data, nowMs: now() });
  } catch (error) { throw mapCallableError(error); }
};

export const tokenHash = (token) => hash(token);
export const tokenIdFor = ({ token, appPackage, deviceHash }) => hash(`${tokenHash(token)}:${appPackage}:${deviceHash}`).slice(0, 48);
export const serverNow = () => FieldValue.serverTimestamp();
export const expiry = (nowMs) => Timestamp.fromMillis(nowMs + 60000);
export async function consumeSelfServiceRateLimit({ firestore, uid, operation, nowMs, limit = 20 }) {
  const actorHash = hash(uid).slice(0, 32); const bucket = Math.floor(nowMs / 60000);
  const ref = firestore.collection('backend_rate_limits').doc(`notification_${actorHash}_${operation}_${bucket}`);
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(ref); const count = current.data()?.count ?? 0;
    if (count >= limit) throw safe('resource-exhausted');
    transaction.set(ref, { actorHash, operation, count: count + 1, expiresAt: Timestamp.fromMillis((bucket + 2) * 60000), updatedAt: FieldValue.serverTimestamp() });
  });
}
export const persistSafeMonitoringEvent = async ({ firestore, uid, event, outcome }) => {
  const actorHash = hash(uid).slice(0, 32);
  await firestore.collection('backend_monitoring_events').doc().create({
    event, outcome, actorHash, createdAt: FieldValue.serverTimestamp(),
  });
};
