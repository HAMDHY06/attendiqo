// REVIEW-ONLY, UNDEPLOYED. Canonical trusted notification outbox writer.
import { createHash } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { SafeCallableError } from './callable_core.mjs';

const templates = {
  parent: new Set(['parentLinkCreated', 'parentLinkRevoked', 'classScheduleChanged', 'instituteNotice']),
  teacher: new Set(['classAssignmentChanged', 'classScheduleChanged', 'instituteNotice', 'accountSecurityAlert']),
  instituteAdmin: new Set(['teacherAccountCreated', 'teacherAccountDisabled', 'projectionFailure', 'systemWarning']),
  superAdmin: new Set(['instituteSuspended', 'instituteReactivated', 'projectionFailure', 'securityAlert']),
};
const routes = new Set(['home', 'myClasses', 'attendance', 'notices', 'profile', 'institutes', 'monitoring', 'audit', 'children', 'childProfile']);
const digest = value => createHash('sha256').update(value).digest('hex');
const reject = () => { throw new SafeCallableError('invalid-argument', 'The request contains invalid information.'); };

export const notificationIdFor = ({ recipientUid, eventType, sourceVersion, deduplicationKey }) =>
  digest(`${recipientUid}:${eventType}:${sourceVersion}:${deduplicationKey}`).slice(0, 48);

const text = (value, max) => typeof value === 'string' && value.trim().length > 0 && value.length <= max;
const safeData = (value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Buffer.byteLength(JSON.stringify(value)) > 1024) reject();
  if (Object.keys(value).some(key => /uid|token|email|phone|path|qr|note/i.test(key))) reject();
  return value;
};
const render = ({ eventType, safeData: data }) => {
  const label = typeof data.label === 'string' && data.label.length <= 80 ? data.label : 'your institute';
  if (eventType === 'parentLinkCreated') return { title: 'Child link updated', body: `A child link is available for ${label}.` };
  if (eventType === 'parentLinkRevoked') return { title: 'Child link updated', body: 'A child link is no longer available.' };
  if (eventType === 'classScheduleChanged') return { title: 'Schedule updated', body: `A class schedule changed at ${label}.` };
  if (eventType === 'instituteNotice') return { title: 'Institute notice', body: `There is a new notice from ${label}.` };
  return { title: 'Attendiqo update', body: `There is an update from ${label}.` };
};

export async function writeNotificationOutbox({ firestore, recipientUid, recipientRole, instituteId = null, eventType, route, safeData: data, sourceVersion, deduplicationKey, priority = 'normal' }) {
  if (!templates[recipientRole]?.has(eventType) || !routes.has(route) || !text(recipientUid, 128) || !text(deduplicationKey, 160)
      || !Number.isInteger(sourceVersion) || sourceVersion < 1 || !['low', 'normal', 'high'].includes(priority)) reject();
  const recipient = await firestore.collection('users').doc(recipientUid).get();
  if (!recipient.exists || recipient.data()?.active !== true || recipient.data()?.role !== recipientRole) {
    throw new SafeCallableError('permission-denied', 'You are not authorized to perform this operation.');
  }
  if (instituteId !== null && recipient.data()?.instituteId !== instituteId && recipientRole !== 'parent') {
    throw new SafeCallableError('permission-denied', 'You are not authorized to perform this operation.');
  }
  const cleanData = safeData(data); const notificationId = notificationIdFor({ recipientUid, eventType, sourceVersion, deduplicationKey });
  const ref = firestore.collection('notification_outbox').doc(notificationId); const message = render({ eventType, safeData: cleanData });
  await firestore.runTransaction(async transaction => {
    const existing = await transaction.get(ref);
    if (existing.exists && (existing.data()?.sourceVersion ?? 0) > sourceVersion) throw new SafeCallableError('failed-precondition', 'The requested operation cannot be completed in the current state.');
    if (existing.exists) return;
    transaction.create(ref, { notificationId, recipientUid, recipientRole, instituteId, eventType, title: message.title, body: message.body, route, safeData: cleanData, priority, status: 'pending', attempts: 0, createdAt: FieldValue.serverTimestamp(), scheduledAt: FieldValue.serverTimestamp(), sentAt: null, sourceVersion, deduplicationKey });
  });
  return { notificationId, status: 'pending' };
}
