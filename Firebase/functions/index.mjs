import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { createCallableBoundary, createParentNoticeBoundary, SafeCallableError } from './lib/callable_core.mjs';
import * as writers from './lib/projection_writers.mjs';
import { listApplicableParentNotices as listTrustedParentNotices } from './lib/parent_notice_feed.mjs';
import { assertSupportedNodeRuntime } from './lib/runtime_guard.mjs';
import { createProjectionTriggers } from './lib/projection_triggers.mjs';
import { createSelfServiceCallableBoundary, consumeSelfServiceRateLimit, persistSafeMonitoringEvent } from './lib/self_service_callable_core.mjs';
import * as notificationDevices from './lib/notification_device_writer.mjs';
import * as notificationPreferences from './lib/notification_preferences_writer.mjs';
import * as instituteMemberships from './lib/institute_membership_writer.mjs';

assertSupportedNodeRuntime();
initializeApp();
const verifyIdToken = async (request) => {
  const authorization = request.rawRequest?.headers?.authorization;
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
    throw new Error('Missing bearer token.');
  }
  return getAuth().verifyIdToken(authorization.slice(7));
};
const boundary = createCallableBoundary({
  firestore: getFirestore(), writers, verifyIdToken,
});

const callable = (operation) => onCall({
  enforceAppCheck: true,
  cors: false,
  timeoutSeconds: 60,
  memory: '256MiB',
}, async (request) => {
  try {
    return await boundary({ operation, request });
  } catch (error) {
    if (error instanceof SafeCallableError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'The operation could not be completed safely.');
  }
});

export const createOrReactivateParentLink = callable('createOrReactivateParentLink');
export const revokeParentStudentLink = callable('revokeParentLink');
export const synchronizeParentStudentProjection = callable('syncStudentProjection');
export const synchronizeParentClassProjection = callable('syncClassProjection');
export const synchronizeParentAttendanceSummary = callable('syncAttendanceSummary');
export const synchronizeParentNotice = callable('syncParentNotice');
export const synchronizeInstitutePublicProfile = callable('syncInstitutePublicProfile');
export const invalidateStudentInstituteLinks = callable('invalidateStudentInstituteLinks');

export const listApplicableParentNotices = onCall({
  enforceAppCheck: true,
  cors: false,
  timeoutSeconds: 30,
  memory: '256MiB',
}, async (request) => {
  const parentBoundary = createParentNoticeBoundary({
    firestore: getFirestore(), listNotices: listTrustedParentNotices,
    verifyIdToken,
  });
  try {
    return await parentBoundary({ request });
  } catch (error) {
    if (error instanceof SafeCallableError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'The operation could not be completed safely.');
  }
});

// REVIEW-ONLY: these exports are deliberately not deployed until trigger and
// reconciliation suites have passed under Node 22 and staging review approves.
const projectionTriggers = createProjectionTriggers({ firestore: getFirestore(), writers });
export const syncParentProjectionForStudent = onDocumentWritten('students/{studentId}', projectionTriggers.onStudentWrite);
export const syncParentProjectionForClass = onDocumentWritten('classes/{classId}', projectionTriggers.onClassWrite);
export const syncParentProjectionForAssignment = onDocumentWritten('class_students/{assignmentId}', projectionTriggers.onAssignmentWrite);
export const syncParentProjectionForSchedule = onDocumentWritten('class_schedule_changes/{changeId}', projectionTriggers.onScheduleWrite);
export const syncParentProjectionForAttendance = onDocumentWritten('attendance_records/{recordId}', projectionTriggers.onAttendanceWrite);
export const syncParentProjectionForAttendanceCorrection = onDocumentWritten('attendance_corrections/{correctionId}', projectionTriggers.onAttendanceCorrectionWrite);
export const syncParentProjectionForInstitute = onDocumentWritten('institutes/{instituteId}', projectionTriggers.onInstituteWrite);

// REVIEW-ONLY, undeployed, App Check protected self-service notification APIs.
const selfService = createSelfServiceCallableBoundary({ firestore: getFirestore(), verifyIdToken });
const selfServiceCallable = (operation, handler) => onCall({ enforceAppCheck: true, cors: false, timeoutSeconds: 30, memory: '256MiB' }, async (request) => {
  try { return await selfService({ request, handler: async (context) => { await consumeSelfServiceRateLimit({ firestore: getFirestore(), uid: context.uid, operation, nowMs: context.nowMs }); const value = await handler(context); await persistSafeMonitoringEvent({ firestore: getFirestore(), uid: context.uid, event: `notification_${operation}`, outcome: 'allowed' }); return value; } }); }
  catch (error) { if (error instanceof SafeCallableError) throw new HttpsError(error.code, error.message); throw new HttpsError('internal', 'The operation could not be completed safely.'); }
});
export const registerNotificationDevice = selfServiceCallable('registerNotificationDevice', (context) => notificationDevices.registerDevice({ firestore: getFirestore(), ...context }));
export const refreshNotificationDevice = selfServiceCallable('refreshNotificationDevice', (context) => notificationDevices.refreshDevice({ firestore: getFirestore(), ...context }));
export const deactivateNotificationDevice = selfServiceCallable('deactivateNotificationDevice', (context) => notificationDevices.deactivateDevice({ firestore: getFirestore(), ...context }));
export const updateNotificationPermissionStatus = selfServiceCallable('updateNotificationPermissionStatus', (context) => notificationDevices.updatePermission({ firestore: getFirestore(), ...context }));
export const getNotificationPreferences = selfServiceCallable('getNotificationPreferences', (context) => notificationPreferences.getPreferences({ firestore: getFirestore(), ...context }));
export const updateNotificationPreferences = selfServiceCallable('updateNotificationPreferences', (context) => notificationPreferences.updatePreferences({ firestore: getFirestore(), ...context }));

// REVIEW-ONLY, undeployed membership approval boundary. Join codes only create
// pending requests; approval remains trusted and scoped.
const membershipCallable = (operation, handler) => onCall({ enforceAppCheck: true, cors: false, timeoutSeconds: 30, memory: '256MiB' }, async (request) => {
  try { return await selfService({ request, handler: context => handler(context) }); }
  catch (error) { if (error instanceof SafeCallableError) throw new HttpsError(error.code, error.message); throw new HttpsError('internal', 'The operation could not be completed safely.'); }
});
export const requestInstituteMembership = membershipCallable('requestInstituteMembership', context => instituteMemberships.submitInstituteJoinRequest({ firestore: getFirestore(), ...context }));
export const approveInstituteMembership = membershipCallable('approveInstituteMembership', context => instituteMemberships.approveInstituteJoinRequest({ firestore: getFirestore(), ...context }));
