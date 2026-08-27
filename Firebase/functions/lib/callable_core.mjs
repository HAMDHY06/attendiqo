import { createHash } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

const operations = new Set([
  'createOrReactivateParentLink', 'revokeParentLink',
  'syncStudentProjection', 'syncClassProjection',
  'syncAttendanceSummary', 'syncParentNotice',
  'syncInstitutePublicProfile', 'invalidateStudentInstituteLinks',
]);

export class SafeCallableError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'SafeCallableError';
    this.code = code;
  }
}

const safeMessages = Object.freeze({
  unauthenticated: 'Authentication is required.',
  'failed-precondition': 'The requested operation cannot be completed in the current state.',
  'permission-denied': 'You are not authorized to perform this operation.',
  'invalid-argument': 'The request contains invalid information.',
  'resource-exhausted': 'Too many requests. Please try again later.',
  aborted: 'The operation is already being processed. Please retry shortly.',
  'not-found': 'The requested record is unavailable.',
  internal: 'The operation could not be completed safely.',
});

const hash = (value) => createHash('sha256').update(value).digest('hex');
const requiredText = (value, label, max = 128) => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  if (!normalized || normalized.length > max) {
    throw new SafeCallableError('invalid-argument', `${label} is invalid.`);
  }
  return normalized;
};
const dataObject = (value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
  }
  return value;
};

export const mapCallableError = (error) => {
  if (error instanceof SafeCallableError) return error;
  const message = String(error?.message ?? '');
  let code = 'internal';
  if (/stale|reactivation|current state/i.test(message)) code = 'failed-precondition';
  else if (/not active|not authorized|cross-institute|do not match|rejected|suspended/i.test(message)) code = 'permission-denied';
  else if (/invalid|requires|missing|must be|unsupported/i.test(message)) code = 'invalid-argument';
  else if (/does not exist|unavailable|not found/i.test(message)) code = 'not-found';
  return new SafeCallableError(code, safeMessages[code]);
};

const safeAudit = async ({ firestore, operation, outcome, code, actorHash, instituteId = null }) => {
  const ref = firestore.collection('backend_callable_audits').doc();
  await ref.create({
    auditId: ref.id, operation, outcome, code, actorHash, instituteId,
    createdAt: FieldValue.serverTimestamp(),
  });
};

const assertAdminForInstitute = async ({ firestore, uid, instituteId }) => {
  const [actorSnap, instituteSnap] = await Promise.all([
    firestore.collection('users').doc(uid).get(),
    firestore.collection('institutes').doc(instituteId).get(),
  ]);
  const actor = actorSnap.data();
  const institute = instituteSnap.data();
  if (!actorSnap.exists || actor?.active !== true || actor?.role !== 'instituteAdmin'
      || actor?.instituteId !== instituteId) {
    throw new SafeCallableError('permission-denied', safeMessages['permission-denied']);
  }
  if (!instituteSnap.exists || institute?.active !== true || institute?.status !== 'active') {
    throw new SafeCallableError('permission-denied', safeMessages['permission-denied']);
  }
};

const consumeRateLimit = async ({ firestore, actorHash, operation, nowMs, maxRequests, windowMs }) => {
  const bucket = Math.floor(nowMs / windowMs);
  const ref = firestore.collection('backend_rate_limits').doc(`${actorHash}_${operation}_${bucket}`);
  await firestore.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const count = snap.data()?.count ?? 0;
    if (count >= maxRequests) {
      throw new SafeCallableError('resource-exhausted', safeMessages['resource-exhausted']);
    }
    transaction.set(ref, {
      actorHash, operation, count: count + 1,
      windowStartedAtMs: bucket * windowMs,
      expiresAt: Timestamp.fromMillis((bucket + 2) * windowMs),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
};

const claimIdempotency = async ({ firestore, actorHash, operation, key, nowMs }) => {
  const ref = firestore.collection('backend_idempotency').doc(hash(`${actorHash}:${operation}:${key}`));
  return firestore.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const existing = snap.data();
    if (existing?.status === 'completed') return { ref, replayed: true };
    if (existing?.status === 'processing' && nowMs - existing.startedAtMs < 300000) {
      throw new SafeCallableError('aborted', safeMessages.aborted);
    }
    transaction.set(ref, {
      actorHash, operation, status: 'processing', startedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(nowMs + 86400000),
    });
    return { ref, replayed: false };
  });
};

const instituteForOperation = async ({ firestore, operation, data }) => {
  if (operation === 'createOrReactivateParentLink' || operation === 'syncStudentProjection') {
    const snap = await firestore.collection('students').doc(requiredText(data.studentId, 'studentId')).get();
    if (!snap.exists) throw new SafeCallableError('not-found', safeMessages['not-found']);
    return snap.data().instituteId;
  }
  if (operation === 'revokeParentLink') {
    const id = `${requiredText(data.parentUid, 'parentUid')}_${requiredText(data.studentId, 'studentId')}`;
    const snap = await firestore.collection('parent_student_links').doc(id).get();
    if (!snap.exists) throw new SafeCallableError('not-found', safeMessages['not-found']);
    return snap.data().instituteId;
  }
  if (operation === 'syncClassProjection') {
    const snap = await firestore.collection('classes').doc(requiredText(data.classId, 'classId')).get();
    if (!snap.exists) throw new SafeCallableError('not-found', safeMessages['not-found']);
    return snap.data().instituteId;
  }
  if (operation === 'syncAttendanceSummary') {
    const sourceCollection = data.sourceCollection ?? 'attendance_records';
    if (sourceCollection !== 'attendance_records') {
      throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
    }
    const snap = await firestore.collection(sourceCollection)
      .doc(requiredText(data.sourceRecordId, 'sourceRecordId')).get();
    if (!snap.exists) throw new SafeCallableError('not-found', safeMessages['not-found']);
    const source = snap.data();
    const [studentSnap, classSnap] = await Promise.all([
      firestore.collection('students').doc(source.studentId).get(),
      firestore.collection('classes').doc(source.classId).get(),
    ]);
    if (!studentSnap.exists || !classSnap.exists || studentSnap.data().active !== true
        || classSnap.data().active !== true || classSnap.data().status === 'archived'
        || studentSnap.data().instituteId !== source.instituteId
        || classSnap.data().instituteId !== source.instituteId) {
      throw new SafeCallableError('permission-denied', safeMessages['permission-denied']);
    }
    return source.instituteId;
  }
  if (operation === 'syncParentNotice') return requiredText(data.notice?.instituteId, 'instituteId');
  if (operation === 'syncInstitutePublicProfile') return requiredText(data.instituteId, 'instituteId');
  if (operation === 'invalidateStudentInstituteLinks') {
    const studentId = requiredText(data.studentId, 'studentId');
    const nextInstituteId = requiredText(data.nextInstituteId, 'nextInstituteId');
    const snap = await firestore.collection('students').doc(studentId).get();
    if (!snap.exists || snap.data().instituteId !== nextInstituteId) {
      throw new SafeCallableError('permission-denied', safeMessages['permission-denied']);
    }
    return nextInstituteId;
  }
  throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
};

const invokeWriter = async ({ writers, firestore, uid, operation, data }) => {
  switch (operation) {
    case 'createOrReactivateParentLink':
      return writers.upsertParentLink({
        firestore, actorUid: uid,
        parentUid: requiredText(data.parentUid, 'parentUid'),
        studentId: requiredText(data.studentId, 'studentId'),
        relationship: requiredText(data.relationship ?? 'parent', 'relationship', 40),
        reactivate: data.reactivate === true,
      });
    case 'revokeParentLink':
      return writers.revokeParentLink({
        firestore, actorUid: uid,
        parentUid: requiredText(data.parentUid, 'parentUid'),
        studentId: requiredText(data.studentId, 'studentId'),
      });
    case 'syncStudentProjection':
      return writers.syncStudentProjection({ firestore, actorUid: uid, studentId: requiredText(data.studentId, 'studentId') });
    case 'syncClassProjection':
      return writers.syncClassProjection({ firestore, actorUid: uid, classId: requiredText(data.classId, 'classId') });
    case 'syncAttendanceSummary':
      return writers.syncAttendanceProjection({
        firestore, actorUid: uid,
        sourceRecordId: requiredText(data.sourceRecordId, 'sourceRecordId'),
      });
    case 'syncParentNotice':
      return writers.publishParentNotice({
        firestore, actorUid: uid,
        notice: { ...dataObject(data.notice), publishedAt: null, sourceVersion: null },
      });
    case 'syncInstitutePublicProfile':
      return writers.syncInstitutePublicProfile({ firestore, actorUid: uid, instituteId: requiredText(data.instituteId, 'instituteId') });
    case 'invalidateStudentInstituteLinks':
      {
        const studentId = requiredText(data.studentId, 'studentId');
        const projection = await firestore.collection('parent_student_profiles').doc(studentId).get();
        if (!projection.exists) {
          throw new SafeCallableError('not-found', safeMessages['not-found']);
        }
      return writers.invalidateStudentLinksForInstituteMove({
        firestore, studentId,
        previousInstituteId: requiredText(projection.data().instituteId, 'previousInstituteId'),
        nextInstituteId: requiredText(data.nextInstituteId, 'nextInstituteId'),
      });
      }
    default:
      throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
  }
};

export const createCallableBoundary = ({
  firestore, writers, requireAppCheck = true,
  maxRequests = 20, windowMs = 60000, now = () => Date.now(),
  onInternalError = () => {},
  verifyIdToken = async (request) => request?.auth,
}) => async ({ operation, request }) => {
  const safeOperation = operations.has(operation) ? operation : 'unknown';
  const uid = request?.auth?.uid;
  const actorHash = hash(uid || 'unauthenticated').slice(0, 32);
  let instituteId = null;
  let idempotencyRef = null;
  try {
    if (!uid) throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    let verifiedToken;
    try {
      verifiedToken = await verifyIdToken(request);
    } catch {
      throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    }
    if (!verifiedToken?.uid || verifiedToken.uid !== uid) {
      throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    }
    if (requireAppCheck && !request?.app?.appId) {
      throw new SafeCallableError('failed-precondition', 'App verification is required.');
    }
    if (!operations.has(operation)) {
      throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
    }
    const data = dataObject(request.data);
    const idempotencyKey = requiredText(data.idempotencyKey, 'idempotencyKey', 128);
    if (idempotencyKey.length < 16) {
      throw new SafeCallableError('invalid-argument', safeMessages['invalid-argument']);
    }
    const nowMs = now();
    await consumeRateLimit({ firestore, actorHash, operation, nowMs, maxRequests, windowMs });
    instituteId = await instituteForOperation({ firestore, operation, data });
    await assertAdminForInstitute({ firestore, uid, instituteId });
    const claim = await claimIdempotency({ firestore, actorHash, operation, key: idempotencyKey, nowMs });
    idempotencyRef = claim.ref;
    if (claim.replayed) {
      await safeAudit({
        firestore, operation, outcome: 'allowed', code: 'idempotent-replay',
        actorHash, instituteId,
      });
      return { ok: true, operation, replayed: true };
    }
    await invokeWriter({ writers, firestore, uid, operation, data });
    await idempotencyRef.set({
      status: 'completed', completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(), safeResult: { ok: true, operation },
    }, { merge: true });
    await safeAudit({ firestore, operation, outcome: 'allowed', code: 'ok', actorHash, instituteId });
    return { ok: true, operation, replayed: false };
  } catch (error) {
    if (!(error instanceof SafeCallableError)) onInternalError(error);
    const safe = mapCallableError(error);
    if (idempotencyRef) {
      await idempotencyRef.set({ status: 'failed', safeCode: safe.code, updatedAt: FieldValue.serverTimestamp() }, { merge: true }).catch(() => {});
    }
    await safeAudit({
      firestore, operation: safeOperation, outcome: 'denied', code: safe.code,
      actorHash, instituteId,
    }).catch(() => {});
    throw safe;
  }
};

// Parent notice reads intentionally use a callable rather than a broad client
// Firestore query.  Firestore rules cannot safely prove both publication and
// expiry predicates for a multi-target query without either leaking notices or
// making valid queries fail.  This boundary keeps the target evaluation on the
// trusted server and never accepts a parent UID from a client.
export const createParentNoticeBoundary = ({
  firestore, listNotices, requireAppCheck = true, maxRequests = 30,
  windowMs = 60000, now = () => Date.now(),
  verifyIdToken = async (request) => request?.auth,
  onInternalError = () => {},
}) => async ({ request }) => {
  const uid = request?.auth?.uid;
  const actorHash = hash(uid || 'unauthenticated').slice(0, 32);
  try {
    if (!uid) throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    let verifiedToken;
    try {
      verifiedToken = await verifyIdToken(request);
    } catch {
      throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    }
    if (verifiedToken?.uid !== uid) {
      throw new SafeCallableError('unauthenticated', safeMessages.unauthenticated);
    }
    if (requireAppCheck && !request?.app?.appId) {
      throw new SafeCallableError('failed-precondition', 'App verification is required.');
    }
    const data = dataObject(request.data ?? {});
    await consumeRateLimit({
      firestore, actorHash, operation: 'listApplicableParentNotices',
      nowMs: now(), maxRequests, windowMs,
    });
    const result = await listNotices({ firestore, parentUid: uid, data, nowMs: now() });
    await safeAudit({
      firestore, operation: 'listApplicableParentNotices', outcome: 'allowed',
      code: 'ok', actorHash,
    });
    return result;
  } catch (error) {
    if (!(error instanceof SafeCallableError)) onInternalError(error);
    const safe = mapCallableError(error);
    await safeAudit({
      firestore, operation: 'listApplicableParentNotices', outcome: 'denied',
      code: safe.code, actorHash,
    }).catch(() => {});
    throw safe;
  }
};
