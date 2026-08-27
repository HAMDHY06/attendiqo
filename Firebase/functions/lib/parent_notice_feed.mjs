// Review-only trusted parent notice reader.  It is deliberately server-side:
// no caller supplied parent ID, student ID, class ID, or institute ID is used
// to broaden the result set.
import { Timestamp } from 'firebase-admin/firestore';
import { SafeCallableError } from './callable_core.mjs';

const text = (value, maximum = 160) => {
  if (typeof value !== 'string' || value.trim().length === 0 || value.trim().length > maximum) {
    throw new SafeCallableError('invalid-argument', 'The request contains invalid information.');
  }
  return value.trim();
};
const millis = (value) => typeof value?.toMillis === 'function' ? value.toMillis() : null;
const activeInstitute = (value) => value?.active === true && value?.status === 'active';
const activeParent = (value) => value?.active === true && value?.role === 'parent';
const unique = (values) => [...new Set(values)];
const priority = (value) => value === 'important' ? 1 : 0;

const safeNotice = (notice) => ({
  noticeId: text(notice.noticeId),
  title: text(notice.title, 140),
  message: text(notice.message, 1200),
  priority: notice.priority === 'important' ? 'important' : 'normal',
  publishedAt: notice.publishedAt,
  expiresAt: notice.expiresAt ?? null,
  targetType: notice.targetType,
});

/**
 * Returns parent-safe notice data only.  The source collection is itself a
 * trusted projection; this function never reads student, class, teacher, or
 * institute source documents except to confirm an institute remains active.
 */
export async function listApplicableParentNotices({ firestore, parentUid, data = {}, nowMs = Date.now() }) {
  const limit = data.limit == null ? 30 : Number(data.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) {
    throw new SafeCallableError('invalid-argument', 'The request contains invalid information.');
  }
  const parentSnap = await firestore.collection('users').doc(parentUid).get();
  if (!parentSnap.exists || !activeParent(parentSnap.data())) {
    throw new SafeCallableError('permission-denied', 'You are not authorized to perform this operation.');
  }
  const links = await firestore.collection('parent_student_links')
    .where('parentUid', '==', parentUid).where('active', '==', true).limit(100).get();
  if (links.empty) return { notices: [], nextPageToken: null };
  const linkValues = links.docs.map((item) => item.data());
  const studentIds = unique(linkValues.map((item) => item.studentId).filter((item) => typeof item === 'string'));
  const instituteIds = unique(linkValues.map((item) => item.instituteId).filter((item) => typeof item === 'string'));
  if (studentIds.length === 0 || instituteIds.length === 0) return { notices: [], nextPageToken: null };
  const profileSnaps = await Promise.all(studentIds.map((studentId) =>
    firestore.collection('parent_student_profiles').doc(studentId).get()));
  const classIds = unique(profileSnaps.flatMap((snap) => {
    const profile = snap.data();
    const link = linkValues.find((value) => value.studentId === snap.id);
    if (!snap.exists || profile?.studentId !== snap.id || profile?.instituteId !== link?.instituteId) return [];
    return Array.isArray(profile.classIds) ? profile.classIds.filter((value) => typeof value === 'string') : [];
  }));
  const instituteSnaps = await Promise.all(instituteIds.map((instituteId) =>
    firestore.collection('institutes').doc(instituteId).get()));
  const readableInstitutes = new Set(instituteSnaps.filter((snap) => activeInstitute(snap.data())).map((snap) => snap.id));
  if (readableInstitutes.size === 0) return { notices: [], nextPageToken: null };
  const snapshots = await Promise.all([...readableInstitutes].map((instituteId) =>
    firestore.collection('parent_notices').where('instituteId', '==', instituteId)
      .where('active', '==', true).orderBy('publishedAt', 'desc').limit(100).get()));
  const notices = new Map();
  for (const snap of snapshots) {
    for (const document of snap.docs) {
      const value = document.data();
      const publishedAt = millis(value.publishedAt);
      const expiresAt = value.expiresAt == null ? null : millis(value.expiresAt);
      if (value.noticeId !== document.id || publishedAt == null || publishedAt > nowMs
          || (expiresAt != null && expiresAt <= nowMs)) continue;
      const targeted = value.targetType === 'instituteParents'
        || (value.targetType === 'student' && (value.targetStudentIds ?? []).some((id) => studentIds.includes(id)))
        || (value.targetType === 'class' && (value.targetClassIds ?? []).some((id) => classIds.includes(id)));
      if (targeted) notices.set(document.id, safeNotice(value));
    }
  }
  const ordered = [...notices.values()].sort((left, right) => priority(right.priority) - priority(left.priority)
    || millis(right.publishedAt) - millis(left.publishedAt)
    || left.noticeId.localeCompare(right.noticeId));
  // The cursor is opaque to UI code and cannot broaden scope: any manipulated
  // cursor can at most omit already-authorized results from the same request.
  const selected = ordered.slice(0, limit);
  const last = selected.at(-1);
  const nextPageToken = ordered.length > selected.length && last
    ? Buffer.from(JSON.stringify({ p: millis(last.publishedAt), n: last.noticeId })).toString('base64url')
    : null;
  return { notices: selected, nextPageToken };
}

export const trustedNow = () => Timestamp.now();
