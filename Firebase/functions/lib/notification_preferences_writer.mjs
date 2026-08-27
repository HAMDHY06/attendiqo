// REVIEW-ONLY callable-only notification preference writer.
import { FieldValue } from 'firebase-admin/firestore';
import { SafeCallableError } from './callable_core.mjs';
const fields = {
  parent: ['attendanceEntry', 'attendanceExit', 'lateAlert', 'absenceAlert', 'scheduleChange', 'notices'],
  teacher: ['classAssignment', 'scheduleChange', 'attendanceReminder', 'notices'],
  instituteAdmin: ['teacherAccountAlerts', 'attendanceAlerts', 'scheduleConflicts', 'systemWarnings', 'notices'],
  superAdmin: ['instituteStatusAlerts', 'projectionFailureAlerts', 'backendFailureAlerts'],
};
const defaults = role => Object.fromEntries([...fields[role], 'securityAlerts'].map(key => [key, true]));
const fail = () => { throw new SafeCallableError('invalid-argument', 'The request contains invalid information.'); };
export async function getPreferences({ firestore, uid, role }) {
  const ref = firestore.collection('notification_preferences').doc(uid); const snap = await ref.get();
  if (!snap.exists) { const value = { uid, ...defaults(role), sourceVersion: 1, updatedAt: FieldValue.serverTimestamp() }; await ref.create(value); return defaults(role); }
  return Object.fromEntries([...fields[role], 'securityAlerts'].map(key => [key, snap.data()[key] ?? true]));
}
export async function updatePreferences({ firestore, uid, role, data }) {
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(key => !fields[role].includes(key)) || Object.values(data).some(value => typeof value !== 'boolean')) fail();
  const current = await getPreferences({ firestore, uid, role });
  await firestore.collection('notification_preferences').doc(uid).set({ ...current, ...data, uid, securityAlerts: true, sourceVersion: 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ...current, ...data, securityAlerts: true };
}
