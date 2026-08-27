// REVIEW-ONLY, UNDEPLOYED, mock-provider only.
import { createHash } from 'node:crypto';
import { SafeCallableError } from './callable_core.mjs';
import { normalizeSriLankanMobile, phoneHash } from './sms_validation.mjs';

const events = new Set(['classScheduleChanged', 'classCancelled', 'urgentInstituteNotice', 'accountInvitation']);
const digest = value => createHash('sha256').update(value).digest('hex').slice(0, 48);
const fail = () => { throw new SafeCallableError('invalid-argument', 'The request contains invalid information.'); };
export async function writeSmsOutbox({ firestore, recipientUid, phone, instituteId, eventType, sourceVersion, deduplicationKey, safeTemplateData = {} }) {
  if (!events.has(eventType) || !Number.isInteger(sourceVersion) || sourceVersion < 1 || typeof deduplicationKey !== 'string' || deduplicationKey.length > 160 || Object.keys(safeTemplateData).some(key => /phone|email|token|qr|note|uid/i.test(key))) fail();
  const recipient = await firestore.collection('users').doc(recipientUid).get();
  if (!recipient.exists || recipient.data()?.active !== true || recipient.data()?.instituteId !== instituteId) throw new SafeCallableError('permission-denied', 'You are not authorized to perform this operation.');
  const protectedPhone = normalizeSriLankanMobile(phone); const recipientPhoneHash = phoneHash(protectedPhone);
  const messageId = digest(`${recipientUid}:${eventType}:${sourceVersion}:${deduplicationKey}`); const ref = firestore.collection('sms_outbox').doc(messageId);
  await firestore.runTransaction(async transaction => { const existing = await transaction.get(ref); if (!existing.exists) transaction.create(ref, { messageId, recipientUid, recipientPhoneHash, protectedPhone, instituteId, eventType, templateId: eventType, safeTemplateData, status: 'pending', attempts: 0, sourceVersion, deduplicationKey }); });
  return { messageId, status: 'pending' };
}
