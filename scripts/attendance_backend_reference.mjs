/**
 * REVIEW-ONLY Admin SDK reference for a future callable function.
 * It is not wired to Firebase exports and must not be deployed as-is.
 */
import { FieldValue } from 'firebase-admin/firestore';
import { attendanceRecordId, authorizeAttendanceActor, validateAttendanceInput } from './lib/attendance_validation.mjs';

export async function recordAttendanceTransaction({ firestore, actorUid, claims = {}, input }) {
  const request = validateAttendanceInput(input);
  return firestore.runTransaction(async (transaction) => {
    const actorRef = firestore.doc(`users/${actorUid}`);
    const sessionRef = firestore.doc(`attendance_sessions/${request.sessionId}`);
    const [actorSnap, sessionSnap] = await Promise.all([transaction.get(actorRef), transaction.get(sessionRef)]);
    if (!actorSnap.exists || !sessionSnap.exists) throw new Error('not-found');
    const actor = { ...actorSnap.data(), uid: actorUid, verifiedSuperAdminClaim: claims.superAdmin === true };
    const session = sessionSnap.data();
    if (session.status !== 'open') throw new Error('session-closed');

    const classRef = firestore.doc(`classes/${session.classId}`);
    const instituteRef = firestore.doc(`institutes/${session.instituteId}`);
    const qrRef = firestore.doc(`qr_tokens/${request.tokenHash}`);
    const [classSnap, instituteSnap, qrSnap] = await Promise.all([
      transaction.get(classRef), transaction.get(instituteRef), transaction.get(qrRef),
    ]);
    if (!classSnap.exists || !instituteSnap.exists || !qrSnap.exists) throw new Error('invalid-qr');
    const academicClass = classSnap.data();
    const institute = instituteSnap.data();
    if (!authorizeAttendanceActor({ actor, academicClass, institute })) throw new Error('permission-denied');
    if (!academicClass.active || academicClass.status !== 'active') throw new Error('class-inactive');

    const credential = qrSnap.data();
    if (!credential.enabled || credential.instituteId !== session.instituteId) throw new Error('invalid-qr');
    const studentRef = firestore.doc(`students/${credential.studentId}`);
    const assignmentRef = firestore.doc(`class_students/${session.classId}_${credential.studentId}`);
    const [studentSnap, assignmentSnap] = await Promise.all([transaction.get(studentRef), transaction.get(assignmentRef)]);
    if (!studentSnap.exists || !assignmentSnap.exists) throw new Error('not-enrolled');
    const student = studentSnap.data();
    const assignment = assignmentSnap.data();
    if (!student.active || student.status !== 'active' || !student.qrEnabled || student.qrVersion !== credential.version) throw new Error('student-inactive');
    if (!assignment.active || assignment.instituteId !== session.instituteId) throw new Error('not-enrolled');

    const id = attendanceRecordId(request.sessionId, credential.studentId);
    const recordRef = firestore.doc(`attendance_records/${id}`);
    const recordSnap = await transaction.get(recordRef);
    const now = FieldValue.serverTimestamp();
    if (request.mode === 'entry') {
      if (recordSnap.exists && recordSnap.data().entryTime) throw new Error('duplicate-entry');
      transaction.set(recordRef, {
        attendanceRecordId: id, sessionId: request.sessionId, instituteId: session.instituteId,
        classId: session.classId, studentId: credential.studentId, attendanceDate: session.date,
        entryTime: now, departureTime: null, status: 'present', lateMinutes: 0,
        entryMarkedBy: actorUid, departureMarkedBy: null, entryDeviceId: request.deviceId,
        departureDeviceId: null, scanMethod: 'qr', manuallyCorrected: false,
        correctionReason: null, correctedBy: null, correctedAt: null, createdAt: now, updatedAt: now,
      }, { merge: false });
    } else {
      if (!recordSnap.exists || !recordSnap.data().entryTime) throw new Error('departure-before-entry');
      if (recordSnap.data().departureTime) throw new Error('duplicate-departure');
      transaction.update(recordRef, { departureTime: now, departureMarkedBy: actorUid,
        departureDeviceId: request.deviceId, updatedAt: now });
    }
    const auditRef = firestore.collection('audit_logs').doc();
    transaction.create(auditRef, {
      auditLogId: auditRef.id, actorUid, actorRole: actor.role, instituteId: session.instituteId,
      action: request.mode === 'entry' ? 'studentEntryRecorded' : 'studentDepartureRecorded',
      targetType: 'attendanceRecord', targetId: id,
      summary: request.mode === 'entry' ? 'Student entry recorded' : 'Student departure recorded',
      createdAt: now,
    });
    return { ok: true, status: 'accepted', attendanceRecordId: id };
  });
}
