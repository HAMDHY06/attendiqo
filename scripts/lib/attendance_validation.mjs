import { createHash } from 'node:crypto';
import { authorizeInstituteActor, authorizeTeacherClassAction } from './role_authorization.mjs';

export const QR_PREFIX = 'attendiqo://student/';

export function hashQrPayload(payload) {
  if (typeof payload !== 'string' || !payload.startsWith(QR_PREFIX)) return null;
  const token = payload.slice(QR_PREFIX.length);
  if (!/^[A-Za-z0-9_-]{40,128}$/.test(token)) return null;
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

export function validateAttendanceInput(input) {
  if (!input || typeof input !== 'object') throw new Error('invalid-request');
  if (typeof input.sessionId !== 'string' || input.sessionId.length > 180) throw new Error('invalid-session');
  if (!['entry', 'departure'].includes(input.mode)) throw new Error('invalid-mode');
  if (typeof input.deviceId !== 'string' || input.deviceId.length < 1 || input.deviceId.length > 160) throw new Error('invalid-device');
  const tokenHash = hashQrPayload(input.qrPayload);
  if (!tokenHash) throw new Error('invalid-qr');
  return { sessionId: input.sessionId, mode: input.mode, deviceId: input.deviceId, tokenHash };
}

export function attendanceRecordId(sessionId, studentId) {
  if (!sessionId || !studentId) throw new Error('invalid-identity');
  return `${sessionId}_${studentId}`;
}

export function authorizeAttendanceActor({ actor, academicClass, institute }) {
  if (actor?.role === 'superAdmin' || actor?.role === 'instituteAdmin') {
    return authorizeInstituteActor({
      actor,
      institute,
      targetInstituteId: academicClass.instituteId,
    });
  }
  return authorizeTeacherClassAction({
    actor,
    institute,
    academicClass,
    permission: 'canTakeAttendance',
  });
}
