import { SmsLedger } from './sms-ledger';
import {
  AppError,
  authenticate,
  normalizeSriLankanMobile,
  safeHash,
  type Fetcher,
  type AuthenticatedUser,
  type FirestoreDocument,
} from './security';
import { createWorkerFirestoreAdmin, type WorkerFirestoreAdmin } from './worker-firestore-admin';

export { SmsLedger };

export interface Env {
  SMS_LEDGER: DurableObjectNamespace<SmsLedger>;
  TEXTLK_API_TOKEN: string;
  TEXTLK_SENDER_ID: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
}

const projectId = 'attendiqo-system';
const defaultMonthlyLimit = 500;
const allowedEvents = new Set([
  'attendanceCheckIn', 'attendanceCheckOut', 'attendanceAbsent', 'attendanceLate',
  'importantNotice', 'emergencyNotice', 'monthlyPaymentReminder',
]);
const manualEvents = new Set(['importantNotice', 'emergencyNotice', 'monthlyPaymentReminder']);
const templates: Record<string, string> = {
  attendanceCheckIn: '{{student}} checked in at {{institute}}.',
  attendanceCheckOut: '{{student}} checked out from {{institute}}.',
  attendanceAbsent: '{{student}} was marked absent today.',
  attendanceLate: '{{student}} was recorded late today.',
  importantNotice: '{{institute}}: Important notice for {{student}}.',
  emergencyNotice: '{{institute}}: Emergency notice regarding {{student}}.',
  monthlyPaymentReminder: '{{institute}}: Monthly payment reminder for {{student}}.',
};

type Json = Record<string, unknown>;

function json(status: number, value: Json): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

function safeError(error: unknown): Response {
  if (error instanceof AppError) return json(error.status, { error: error.code, message: error.safeMessage });
  return json(500, { error: 'internal', message: 'The SMS request could not be completed.' });
}

async function body(request: Request): Promise<Json> {
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > 4096) throw new AppError(413, 'payload_too_large', 'The request is too large.');
  const parsed = await request.json().catch(() => { throw new AppError(400, 'invalid_payload', 'The request is invalid.'); });
  if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') throw new AppError(400, 'invalid_payload', 'The request is invalid.');
  return parsed as Json;
}

function exact(value: Json, fields: string[]) {
  for (const key of Object.keys(value)) if (!fields.includes(key)) throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
}

function string(value: unknown, field: string, max = 160): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  return value.trim();
}

function roleCanSend(user: AuthenticatedUser): boolean {
  return user.role === 'superAdmin' || user.role === 'instituteAdmin';
}

function getField<T>(document: FirestoreDocument, key: string): T | undefined { return document.fields[key] as T | undefined; }

async function verifiedUser(
  request: Request,
  firestore: WorkerFirestoreAdmin,
  requestFetch: Fetcher,
): Promise<AuthenticatedUser> {
  const user = await authenticate(request, projectId, firestore.get, requestFetch);
  if (!user.active) throw new AppError(403, 'inactive_account', 'This account is not active.');
  if (user.role !== 'superAdmin' && user.role !== 'instituteAdmin' && user.role !== 'teacher' && user.role !== 'parent') throw new AppError(403, 'unsupported_role', 'This account is not permitted to use SMS.');
  if (user.role !== 'superAdmin' && user.instituteId) {
    const institute = await firestore.get(`institutes/${user.instituteId}`);
    if (!institute || getField<boolean>(institute, 'active') !== true || getField<string>(institute, 'status') === 'suspended') throw new AppError(403, 'suspended_institute', 'This institute is not active.');
  }
  return user;
}

async function scopedInstitute(firestore: WorkerFirestoreAdmin, user: AuthenticatedUser, requested: unknown): Promise<string> {
  if (user.role === 'superAdmin') {
    const instituteId = string(requested, 'instituteId', 128);
    if (!await firestore.get(`institutes/${instituteId}`)) throw new AppError(404, 'institute_unavailable', 'This institute is unavailable.');
    return instituteId;
  }
  if (requested !== undefined) throw new AppError(400, 'forbidden_scope', 'The institute is derived from your account.');
  if (!user.instituteId) throw new AppError(403, 'missing_institute', 'This account is not scoped to an active institute.');
  return user.instituteId;
}

async function settings(ledger: DurableObjectStub, instituteId: string) {
  return ledger.fetch('https://ledger/settings', { method: 'POST', body: JSON.stringify({ instituteId, defaultMonthlyLimit }) }).then(r => r.json<Json>());
}

function safeTemplate(value: string): string {
  if (value.length > 160 || /https?:\/\/|\+?\d{7,}|[\r\n]/i.test(value)) throw new AppError(400, 'invalid_template', 'The template contains unsupported content.');
  const stripped = value.replace(/\{\{(student|institute|date)\}\}/g, '');
  if (/\{\{[^}]+\}\}/.test(stripped)) throw new AppError(400, 'invalid_template', 'The template contains an unsupported placeholder.');
  return value.trim();
}

async function sendSms(
  env: Env,
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
  requestFetch: Fetcher = fetch,
): Promise<Response> {
  exact(payload, ['studentId', 'eventType', 'sourceEventKey']);
  if (!roleCanSend(user)) throw new AppError(403, 'forbidden', 'This account cannot request SMS delivery.');
  const studentId = string(payload.studentId, 'studentId', 128);
  const eventType = string(payload.eventType, 'eventType', 64);
  const sourceEventKey = string(payload.sourceEventKey, 'sourceEventKey', 128);
  if (!allowedEvents.has(eventType)) throw new AppError(400, 'unsupported_event', 'The SMS event is unsupported.');
  if (!manualEvents.has(eventType)) throw new AppError(409, 'attendance_unavailable', 'Attendance SMS is unavailable until the trusted attendance backend is deployed.');
  const student = await firestore.get(`students/${studentId}`);
  if (!student || getField<boolean>(student, 'active') !== true) throw new AppError(404, 'recipient_unavailable', 'A valid SMS recipient is unavailable.');
  const instituteId = getField<string>(student, 'instituteId');
  if (!instituteId || (user.role !== 'superAdmin' && instituteId !== user.instituteId)) throw new AppError(403, 'cross_institute', 'This student is outside your institute.');
  const consent = await firestore.get(`student_sms_consents/${studentId}`);
  if (!consent || getField<boolean>(consent, 'granted') !== true || getField<string>(consent, 'instituteId') !== instituteId) throw new AppError(409, 'consent_required', 'SMS consent is required for this student.');
  const phone = normalizeSriLankanMobile(getField<string>(student, 'primaryParentMobile'));
  const ledger = env.SMS_LEDGER.getByName(instituteId);
  const config = await settings(ledger, instituteId);
  if (config.enabled !== true || !(config.allowedEvents as string[]).includes(eventType)) throw new AppError(409, 'sms_disabled', 'SMS is not enabled for this event.');
  const notificationId = await safeHash(`${instituteId}:${studentId}:${eventType}:${sourceEventKey}`);
  const reserved = await ledger.fetch('https://ledger/reserve', { method: 'POST', body: JSON.stringify({ notificationId, eventType, monthlyLimit: config.monthlyLimit }) }).then(r => r.json<Json>());
  if (reserved.status === 'duplicate') return json(200, { status: 'duplicate' });
  if (reserved.status !== 'reserved') throw new AppError(429, 'quota_exceeded', 'The institute SMS limit has been reached.');
  const studentName = getField<string>(student, 'fullName')?.split(/\s+/)[0] ?? 'Student';
  const institute = await firestore.get(`institutes/${instituteId}`);
  const instituteName = getField<string>(institute ?? { fields: {} }, 'name') ?? 'Your institute';
  const template = ((config.templates as Json | undefined)?.[eventType] as string | undefined) ?? templates[eventType];
  const rendered = template.replaceAll('{{student}}', studentName).replaceAll('{{institute}}', instituteName).replaceAll('{{date}}', new Date().toISOString().slice(0, 10));
  let status = 'failed';
  try {
    const response = await requestFetch('https://app.text.lk/api/v3/sms/send', { method: 'POST', headers: { authorization: `Bearer ${env.TEXTLK_API_TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ recipient: phone, sender_id: env.TEXTLK_SENDER_ID, type: 'plain', message: rendered }) });
    status = response.ok ? 'sent' : 'retry';
  } finally {
    await ledger.fetch('https://ledger/complete', { method: 'POST', body: JSON.stringify({ notificationId, status }) });
  }
  return json(status === 'sent' ? 202 : 503, { status });
}

const membershipRoles = new Set(['instituteAdmin', 'teacher', 'parent']);

function activeInstitute(document: FirestoreDocument | undefined): boolean {
  return document != null && getField<boolean>(document, 'active') === true && getField<string>(document, 'status') !== 'suspended';
}

type MembershipRole = 'instituteAdmin' | 'teacher' | 'parent';

async function hasActiveInstituteAdmin(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  instituteId: string,
): Promise<boolean> {
  if (user.role === 'superAdmin' && user.superAdmin) return true;
  if (!activeInstitute(await firestore.get(`institutes/${instituteId}`))) return false;
  return (await firestore.queryMemberships(user.uid)).some(
    (membership) =>
        getField<string>(membership, 'instituteId') === instituteId &&
        getField<string>(membership, 'role') === 'instituteAdmin' &&
        getField<string>(membership, 'status') === 'active',
  );
}

function safeRequest(document: FirestoreDocument): Json | undefined {
  const requestId = getField<string>(document, 'requestId');
  const instituteId = getField<string>(document, 'instituteId');
  const requestedRole = getField<string>(document, 'requestedRole');
  const status = getField<string>(document, 'status');
  if (!requestId || !instituteId || !requestedRole || !status) return undefined;
  return { requestId, instituteId, requestedRole, status };
}

async function requestMembership(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
): Promise<Response> {
  exact(payload, ['joinCode', 'requestedRole']);
  const joinCode = string(payload.joinCode, 'joinCode', 24).toUpperCase();
  const requestedRole = string(payload.requestedRole, 'requestedRole', 32);
  if (!/^[A-Z0-9][A-Z0-9-]{5,23}$/.test(joinCode) || !membershipRoles.has(requestedRole)) {
    throw new AppError(400, 'invalid_payload', 'The membership request is invalid.');
  }
  const code = await firestore.get(`institute_join_codes/${joinCode}`);
  const instituteId = getField<string>(code ?? { fields: {} }, 'instituteId');
  if (!code || getField<boolean>(code, 'active') !== true || !instituteId || !activeInstitute(await firestore.get(`institutes/${instituteId}`))) {
    throw new AppError(404, 'institute_unavailable', 'This institute is unavailable.');
  }
  const membershipId = `${user.uid}_${instituteId}`;
  const existingMembership = await firestore.get(`institute_memberships/${membershipId}`);
  if (existingMembership && getField<string>(existingMembership, 'status') === 'active') {
    return json(200, { status: 'active' });
  }
  const requestId = `${user.uid}_${instituteId}_${requestedRole}`;
  const existing = await firestore.get(`institute_join_requests/${requestId}`);
  if (existing && getField<string>(existing, 'status') === 'pending') return json(200, { status: 'pending' });
  const now = new Date().toISOString();
  await firestore.commit([{ path: `institute_join_requests/${requestId}`, createOnly: !existing, updateTime: existing?.updateTime, fields: {
    requestId, uid: user.uid, instituteId, requestedRole, status: 'pending', requestedAt: now, updatedAt: now,
  } }]);
  return json(202, { status: 'pending' });
}

async function reviewMembership(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
): Promise<Response> {
  exact(payload, ['requestId', 'decision']);
  const requestId = string(payload.requestId, 'requestId', 256);
  const decision = string(payload.decision, 'decision', 16);
  if (!['approve', 'reject'].includes(decision)) throw new AppError(400, 'invalid_payload', 'The membership review is invalid.');
  const request = await firestore.get(`institute_join_requests/${requestId}`);
  const instituteId = getField<string>(request ?? { fields: {} }, 'instituteId');
  const requestedRole = getField<string>(request ?? { fields: {} }, 'requestedRole');
  const requestedUid = getField<string>(request ?? { fields: {} }, 'uid');
  if (!request || !instituteId || !requestedUid || !requestedRole || getField<string>(request, 'status') !== 'pending') {
    throw new AppError(404, 'request_unavailable', 'This membership request is unavailable.');
  }
  const isSuperAdmin = user.role === 'superAdmin' && user.superAdmin;
  const mayReview = isSuperAdmin || (
    (requestedRole === 'teacher' || requestedRole === 'parent') &&
    await hasActiveInstituteAdmin(firestore, user, instituteId)
  );
  if (!mayReview || (!isSuperAdmin && requestedRole === 'instituteAdmin')) {
    throw new AppError(403, 'forbidden', 'You are not permitted to review this request.');
  }
  const now = new Date().toISOString();
  const membershipId = `${requestedUid}_${instituteId}`;
  const writes: Array<{ path: string; fields: Json; updateTime?: string; createOnly?: boolean }> = [{
    path: `institute_join_requests/${requestId}`,
    updateTime: request.updateTime,
    fields: { ...request.fields, status: decision === 'approve' ? 'active' : 'rejected', reviewedAt: now, reviewedBy: user.uid, updatedAt: now },
  }];
  if (decision === 'approve') {
    const membership = await firestore.get(`institute_memberships/${membershipId}`);
    writes.push({
      path: `institute_memberships/${membershipId}`,
      createOnly: !membership,
      updateTime: membership?.updateTime,
      fields: {
        uid: requestedUid, instituteId, role: requestedRole, status: 'active',
        requestedAt: getField<string>(request, 'requestedAt') ?? now,
        approvedAt: now, approvedBy: user.uid, reviewedAt: now, reviewedBy: user.uid, updatedAt: now,
      },
    });
  }
  await firestore.commit(writes);
  return json(200, { status: decision === 'approve' ? 'active' : 'rejected' });
}

async function revokeMembership(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
): Promise<Response> {
  exact(payload, ['membershipId']);
  const membershipId = string(payload.membershipId, 'membershipId', 256);
  const membership = await firestore.get(`institute_memberships/${membershipId}`);
  const instituteId = getField<string>(membership ?? { fields: {} }, 'instituteId');
  const role = getField<string>(membership ?? { fields: {} }, 'role');
  if (!membership || !instituteId || !role || getField<string>(membership, 'status') !== 'active') {
    throw new AppError(404, 'membership_unavailable', 'This membership is unavailable.');
  }
  const isSuperAdmin = user.role === 'superAdmin' && user.superAdmin;
  const mayRevoke = isSuperAdmin || (
    (role === 'teacher' || role === 'parent') &&
    await hasActiveInstituteAdmin(firestore, user, instituteId)
  );
  if (!mayRevoke) throw new AppError(403, 'forbidden', 'You are not permitted to revoke this membership.');
  const now = new Date().toISOString();
  await firestore.commit([{ path: `institute_memberships/${membershipId}`, updateTime: membership.updateTime, fields: {
    ...membership.fields, status: 'revoked', revokedAt: now, revokedBy: user.uid, updatedAt: now,
  } }]);
  return json(200, { status: 'revoked' });
}

async function listOwnRequests(firestore: WorkerFirestoreAdmin, user: AuthenticatedUser): Promise<Response> {
  const requests = (await firestore.queryJoinRequests('uid', user.uid))
    .map(safeRequest).filter((value): value is Json => value != null);
  return json(200, { requests });
}

async function listReviewableRequests(firestore: WorkerFirestoreAdmin, user: AuthenticatedUser): Promise<Response> {
  const isSuperAdmin = user.role === 'superAdmin' && user.superAdmin;
  if (!isSuperAdmin && user.role !== 'instituteAdmin') {
    throw new AppError(403, 'forbidden', 'You are not permitted to review membership requests.');
  }
  const memberships = isSuperAdmin ? [] : await firestore.queryMemberships(user.uid);
  const instituteIds = isSuperAdmin
    ? []
    : memberships.filter((item) => getField<string>(item, 'role') === 'instituteAdmin' && getField<string>(item, 'status') === 'active')
      .map((item) => getField<string>(item, 'instituteId')).filter((value): value is string => !!value);
  const entries = isSuperAdmin
    ? await firestore.queryPendingInstituteAdminRequests()
    : (await Promise.all(instituteIds.map((id) => firestore.queryJoinRequests('instituteId', id)))).flat();
  const requests = entries
    .filter((item) => {
      const requestedRole = getField<string>(item, 'requestedRole');
      return isSuperAdmin ? requestedRole === 'instituteAdmin' : requestedRole === 'teacher' || requestedRole === 'parent';
    })
    .map(safeRequest).filter((value): value is Json => value != null);
  return json(200, { requests });
}

async function listMemberships(firestore: WorkerFirestoreAdmin, user: AuthenticatedUser): Promise<Response> {
  const memberships = await firestore.queryMemberships(user.uid);
  const safe = memberships
    .filter((item) => getField<string>(item, 'uid') === user.uid)
    .map((item) => ({ instituteId: getField<string>(item, 'instituteId'), role: getField<string>(item, 'role'), status: getField<string>(item, 'status') }))
    .filter((item) => typeof item.instituteId === 'string' && typeof item.role === 'string' && typeof item.status === 'string');
  return json(200, { memberships: safe });
}

export async function handle(
  request: Request,
  env: Env,
  requestFetch: Fetcher = fetch,
  testOnly?: { signedAssertionProvider?: () => Promise<string> },
): Promise<Response> {
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed', message: 'Use POST.' });
  // Reject unauthenticated traffic before parsing or using the backend-only
  // service-account secret. This keeps public endpoint probes deterministic
  // and ensures unavailable backend credentials cannot mask an auth denial.
  if (!request.headers.get('authorization')?.startsWith('Bearer ')) {
    return json(401, { error: 'unauthenticated', message: 'Sign in to use SMS.' });
  }
  const firestore = createWorkerFirestoreAdmin(
    env.FIREBASE_SERVICE_ACCOUNT_JSON,
    requestFetch,
    testOnly,
  );
  const user = await verifiedUser(request, firestore, requestFetch);
  const payload = await body(request);
  if (new URL(request.url).pathname === '/v1/send') return sendSms(env, firestore, user, payload, requestFetch);
  if (new URL(request.url).pathname === '/v1/memberships/request') return requestMembership(firestore, user, payload);
  if (new URL(request.url).pathname === '/v1/memberships/review') return reviewMembership(firestore, user, payload);
  if (new URL(request.url).pathname === '/v1/memberships/revoke') return revokeMembership(firestore, user, payload);
  if (new URL(request.url).pathname === '/v1/memberships/requests/list') { exact(payload, []); return listOwnRequests(firestore, user); }
  if (new URL(request.url).pathname === '/v1/memberships/reviewable') { exact(payload, []); return listReviewableRequests(firestore, user); }
  if (new URL(request.url).pathname === '/v1/memberships/list') {
    exact(payload, []);
    return listMemberships(firestore, user);
  }
  if (new URL(request.url).pathname === '/v1/usage') {
    exact(payload, ['instituteId']); const instituteId = await scopedInstitute(firestore, user, payload.instituteId);
    const value = await env.SMS_LEDGER.getByName(instituteId).fetch('https://ledger/usage', { method: 'POST', body: JSON.stringify({ instituteId, defaultMonthlyLimit }) });
    return new Response(value.body, { status: value.status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
  }
  if (new URL(request.url).pathname === '/v1/settings') {
    if (!roleCanSend(user)) throw new AppError(403, 'forbidden', 'This account cannot manage SMS settings.');
    exact(payload, ['instituteId', 'enabled', 'monthlyLimit', 'allowedEvents', 'templates']); const instituteId = await scopedInstitute(firestore, user, payload.instituteId);
    const allowed = payload.allowedEvents;
    if (!Array.isArray(allowed) || !allowed.every(v => typeof v === 'string' && allowedEvents.has(v))) throw new AppError(400, 'invalid_payload', 'The allowed SMS events are invalid.');
    const limit = (payload.monthlyLimit ?? defaultMonthlyLimit) as number;
    if (!Number.isInteger(limit) || limit < 0 || limit > 100000 || typeof payload.enabled !== 'boolean') throw new AppError(400, 'invalid_payload', 'The SMS settings are invalid.');
    const configuredTemplates = payload.templates ?? {};
    if (!configuredTemplates || Array.isArray(configuredTemplates) || typeof configuredTemplates !== 'object' || !Object.entries(configuredTemplates as Json).every(([event, value]) => allowedEvents.has(event) && typeof value === 'string' && safeTemplate(value) === value.trim())) throw new AppError(400, 'invalid_template', 'The SMS templates are invalid.');
    const result = await env.SMS_LEDGER.getByName(instituteId).fetch('https://ledger/settings-update', { method: 'POST', body: JSON.stringify({ instituteId, enabled: payload.enabled, monthlyLimit: limit, allowedEvents: allowed, templates: configuredTemplates, defaultMonthlyLimit }) });
    return new Response(result.body, { status: result.status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
  }
  return json(404, { error: 'not_found', message: 'The SMS endpoint was not found.' });
}

export default {
  fetch: (request, env) => handle(request, env).catch(safeError),
} satisfies ExportedHandler<Env>;
