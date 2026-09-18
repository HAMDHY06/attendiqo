import { AppError, type AuthenticatedUser } from './security';
import { firestoreTimestamp, type WorkerFirestoreAdmin } from './worker-firestore-admin';

type Json = Record<string, unknown>;
type Context = { firestore: WorkerFirestoreAdmin; user: AuthenticatedUser; payload: Json };

function exact(value: Json, fields: string[]) {
  for (const key of Object.keys(value)) if (!fields.includes(key)) throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
}
function text(value: unknown, field: string, max: number, optional = false): string {
  if (optional && value === '') return '';
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  return value.trim();
}
function requireSuperAdmin(user: AuthenticatedUser) {
  if (user.role !== 'superAdmin' || !user.superAdmin || !user.active) throw new AppError(403, 'forbidden', 'Verified Super Admin access is required.');
}
function editable(payload: Json) {
  const instituteCode = text(payload.instituteCode, 'instituteCode', 24).toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{1,23}$/.test(instituteCode)) throw new AppError(400, 'invalid_payload', 'The institute code is invalid.');
  const status = text(payload.status, 'status', 16);
  if (!['active', 'suspended', 'inactive'].includes(status)) throw new AppError(400, 'invalid_payload', 'The institute status is invalid.');
  const bools = ['pushNotificationsEnabled', 'smsEnabled', 'allowPaidExtraSms'];
  if (bools.some((key) => typeof payload[key] !== 'boolean') || !Number.isInteger(payload.smsMonthlyLimit) || Number(payload.smsMonthlyLimit) < 0) throw new AppError(400, 'invalid_payload', 'The institute settings are invalid.');
  return {
    instituteCode,
    name: text(payload.name, 'name', 160), address: text(payload.address, 'address', 500, true),
    contactNumber: text(payload.contactNumber, 'contactNumber', 24), email: text(payload.email, 'email', 254, true),
    active: status === 'active', status,
    pushNotificationsEnabled: payload.pushNotificationsEnabled as boolean,
    smsEnabled: payload.smsEnabled as boolean,
    smsMonthlyLimit: payload.smsMonthlyLimit as number,
    allowPaidExtraSms: payload.allowPaidExtraSms as boolean,
  };
}
const fields = ['instituteId','instituteCode','name','address','contactNumber','email','status','pushNotificationsEnabled','smsEnabled','smsMonthlyLimit','allowPaidExtraSms'];

export async function createInstitute({ firestore, user, payload }: Context): Promise<Json> {
  requireSuperAdmin(user); exact(payload, fields);
  const instituteId = text(payload.instituteId, 'instituteId', 128);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(instituteId)) throw new AppError(400, 'invalid_payload', 'The institute identifier is invalid.');
  const value = editable(payload);
  if (await firestore.get(`institute_codes/${value.instituteCode}`)) throw new AppError(409, 'duplicate_code', 'That institute code is already in use.');
  const now = new Date().toISOString(); const auditLogId = crypto.randomUUID();
  const document = { instituteId, ...value, smsUsedThisMonth: 0, createdAt: firestoreTimestamp(now), createdBy: user.uid, updatedAt: firestoreTimestamp(now), updatedBy: user.uid };
  await firestore.commit([
    { path: `institute_codes/${value.instituteCode}`, createOnly: true, fields: { instituteId, createdAt: firestoreTimestamp(now), createdBy: user.uid } },
    { path: `institutes/${instituteId}`, createOnly: true, fields: document },
    { path: `audit_logs/${auditLogId}`, createOnly: true, fields: { auditLogId, actorUid: user.uid, actorRole: 'superAdmin', instituteId, action: 'instituteCreated', targetType: 'institute', targetId: instituteId, summary: `Institute ${value.instituteCode} created`, createdAt: firestoreTimestamp(now) } },
  ]);
  return { institute: { ...document, createdAt: now, updatedAt: now } };
}

export async function updateInstitute({ firestore, user, payload }: Context): Promise<Json> {
  requireSuperAdmin(user); exact(payload, fields);
  const instituteId = text(payload.instituteId, 'instituteId', 128); const current = await firestore.get(`institutes/${instituteId}`);
  if (!current) throw new AppError(404, 'not_found', 'The institute was not found.');
  const value = editable(payload);
  if (current.fields.instituteCode !== value.instituteCode) throw new AppError(409, 'immutable_code', 'The institute code cannot be changed.');
  const now = new Date().toISOString(); const auditLogId = crypto.randomUUID();
  const action = current.fields.status !== value.status
    ? (value.status === 'active' ? 'instituteActivated' : 'instituteSuspended')
    : current.fields.smsEnabled !== value.smsEnabled || current.fields.smsMonthlyLimit !== value.smsMonthlyLimit || current.fields.allowPaidExtraSms !== value.allowPaidExtraSms
      ? 'smsSettingChanged'
      : current.fields.pushNotificationsEnabled !== value.pushNotificationsEnabled
        ? 'pushSettingChanged'
        : 'instituteUpdated';
  const document = { ...current.fields, ...value, instituteId, updatedAt: firestoreTimestamp(now), updatedBy: user.uid };
  await firestore.commit([
    { path: `institutes/${instituteId}`, updateTime: current.updateTime, fields: document },
    { path: `audit_logs/${auditLogId}`, createOnly: true, fields: { auditLogId, actorUid: user.uid, actorRole: 'superAdmin', instituteId, action, targetType: action === 'smsSettingChanged' ? 'smsSettings' : action === 'pushSettingChanged' ? 'pushSettings' : 'institute', targetId: instituteId, summary: `${action}: ${value.instituteCode}`, createdAt: firestoreTimestamp(now) } },
  ]);
  return { institute: { ...document, updatedAt: now } };
}
