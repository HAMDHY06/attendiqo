// REVIEW-ONLY trusted membership writer. Mobile clients never write these
// records directly; a visible join code only creates a pending request.
import { FieldValue } from 'firebase-admin/firestore';
import { SafeCallableError } from './callable_core.mjs';

const fail = (code = 'invalid-argument') => { throw new SafeCallableError(code, {
  'invalid-argument': 'The request contains invalid information.',
  'permission-denied': 'You are not authorized to perform this operation.',
  'not-found': 'The requested record is unavailable.',
  'failed-precondition': 'The requested operation cannot be completed in the current state.',
}[code]); };
const roles = new Set(['instituteAdmin', 'teacher', 'parent']);
const exact = (data, fields) => {
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(key => !fields.has(key))) fail();
};
const code = (value) => {
  const result = typeof value === 'string' ? value.trim().toUpperCase() : '';
  if (!/^[A-Z0-9][A-Z0-9-]{5,23}$/.test(result)) fail();
  return result;
};
const role = (value) => { if (!roles.has(value)) fail(); return value; };

export async function submitInstituteJoinRequest({ firestore, uid, data }) {
  exact(data, new Set(['joinCode', 'requestedRole']));
  const joinCode = code(data.joinCode); const requestedRole = role(data.requestedRole);
  const codeSnap = await firestore.collection('institute_join_codes').doc(joinCode).get();
  const instituteId = codeSnap.data()?.instituteId;
  if (!codeSnap.exists || codeSnap.data()?.active !== true || typeof instituteId !== 'string') fail('not-found');
  const institute = await firestore.collection('institutes').doc(instituteId).get();
  if (!institute.exists || institute.data()?.active !== true || institute.data()?.status !== 'active') fail('failed-precondition');
  const requestId = `${uid}_${instituteId}_${requestedRole}`;
  const membershipId = `${uid}_${instituteId}`;
  return firestore.runTransaction(async transaction => {
    const [request, membership] = await Promise.all([
      transaction.get(firestore.collection('institute_join_requests').doc(requestId)),
      transaction.get(firestore.collection('institute_memberships').doc(membershipId)),
    ]);
    if (membership.data()?.status === 'active' && membership.data()?.role === requestedRole) {
      return { status: 'active' };
    }
    if (request.data()?.status === 'pending') return { status: 'pending' };
    transaction.set(firestore.collection('institute_join_requests').doc(requestId), {
      requestId, uid, instituteId, requestedRole, status: 'pending', requestedAt: FieldValue.serverTimestamp(),
      reviewedAt: null, reviewedBy: null,
    });
    return { status: 'pending' };
  });
}

export async function approveInstituteJoinRequest({ firestore, uid, role: reviewerRole, instituteId: reviewerInstituteId, claims, data }) {
  exact(data, new Set(['requestId']));
  const requestId = typeof data.requestId === 'string' ? data.requestId.trim() : '';
  if (!requestId || requestId.length > 300) fail();
  const requestRef = firestore.collection('institute_join_requests').doc(requestId);
  return firestore.runTransaction(async transaction => {
    const requestSnap = await transaction.get(requestRef); const request = requestSnap.data();
    if (!requestSnap.exists || request?.status !== 'pending' || !roles.has(request.requestedRole)) fail('not-found');
    const isVerifiedSuper = reviewerRole === 'superAdmin' && claims?.superAdmin === true;
    const isOwnInstituteAdmin = reviewerRole === 'instituteAdmin' && reviewerInstituteId === request.instituteId;
    if ((request.requestedRole === 'instituteAdmin' && !isVerifiedSuper) ||
        (request.requestedRole !== 'instituteAdmin' && !isVerifiedSuper && !isOwnInstituteAdmin)) fail('permission-denied');
    const membershipId = `${request.uid}_${request.instituteId}`;
    transaction.set(firestore.collection('institute_memberships').doc(membershipId), {
      uid: request.uid, instituteId: request.instituteId, role: request.requestedRole, status: 'active',
      requestedAt: request.requestedAt ?? FieldValue.serverTimestamp(), approvedAt: FieldValue.serverTimestamp(), approvedBy: uid,
      reviewedAt: FieldValue.serverTimestamp(), reviewedBy: uid,
    }, { merge: true });
    transaction.update(requestRef, { status: 'active', reviewedAt: FieldValue.serverTimestamp(), reviewedBy: uid });
    return { status: 'active' };
  });
}
