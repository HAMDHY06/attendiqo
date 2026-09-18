import { AppError, safeHash, type AuthenticatedUser, type FirestoreDocument } from './security';
import {
  firestoreTimestamp,
  type WorkerFirestoreAdmin,
} from './worker-firestore-admin';

type Json = Record<string, unknown>;
type AttendanceContext = {
  firestore: WorkerFirestoreAdmin;
  user: AuthenticatedUser;
  payload: Json;
  notify?: (event: { studentId: string; status: string; mode?: string }) => Promise<void>;
};

const idPattern = /^[A-Za-z0-9_-]{1,128}$/;
const hashPattern = /^[a-f0-9]{64}$/;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const timePattern = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const statuses = new Set(['present', 'absent', 'late', 'excused']);

function exact(value: Json, fields: string[]): void {
  for (const key of Object.keys(value)) {
    if (!fields.includes(key)) {
      throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
    }
  }
}

function text(value: unknown, field: string, max = 128): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) {
    throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  }
  return value.trim();
}

function field<T>(document: FirestoreDocument, key: string): T | undefined {
  return document.fields[key] as T | undefined;
}

function timeValue(value: unknown, fieldName: string): string {
  const result = text(value, fieldName, 5);
  if (!timePattern.test(result)) throw new AppError(400, 'invalid_payload', `The ${fieldName} is invalid.`);
  return result;
}

function isoDate(value: unknown): string {
  const result = text(value, 'date', 10);
  if (!datePattern.test(result) || Number.isNaN(Date.parse(`${result}T00:00:00.000Z`))) {
    throw new AppError(400, 'invalid_payload', 'The date is invalid.');
  }
  return result;
}

function timestamp(value: unknown): string | undefined {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return undefined;
  return new Date(value).toISOString();
}

function activeSuperAdmin(user: AuthenticatedUser): boolean {
  return user.role === 'superAdmin' && user.superAdmin;
}

function permission(profile: FirestoreDocument, name: string): boolean {
  const permissions = field<Json>(profile, 'permissions');
  return permissions?.[name] === true;
}

function activeClass(value: FirestoreDocument): boolean {
  return field<boolean>(value, 'active') === true && field<string>(value, 'status') === 'active';
}

async function authorizeClass(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  academicClass: FirestoreDocument,
  requiredPermission: 'canTakeAttendance' | 'canCorrectAttendance' | 'canGenerateQrCodes',
): Promise<void> {
  const instituteId = field<string>(academicClass, 'instituteId');
  if (!instituteId || !activeClass(academicClass)) {
    throw new AppError(409, 'class_inactive', 'This class is not active.');
  }
  if (activeSuperAdmin(user)) return;
  if (user.instituteId !== instituteId) {
    throw new AppError(403, 'cross_institute', 'This class is outside your institute.');
  }
  if (user.role === 'instituteAdmin') return;
  const teachers = field<unknown[]>(academicClass, 'teacherIds');
  const profile = await firestore.get(`users/${user.uid}`);
  if (
    user.role !== 'teacher' ||
    !Array.isArray(teachers) ||
    !teachers.includes(user.uid) ||
    !profile ||
    !permission(profile, requiredPermission)
  ) {
    throw new AppError(403, 'forbidden', 'You are not permitted to perform this attendance action.');
  }
}

function audit(
  user: AuthenticatedUser,
  instituteId: string,
  action: string,
  targetType: string,
  targetId: string,
  summary: string,
  now: string,
): { path: string; fields: Json; createOnly: true } {
  const auditLogId = crypto.randomUUID();
  return {
    path: `audit_logs/${auditLogId}`,
    createOnly: true,
    fields: {
      auditLogId,
      actorUid: user.uid,
      actorRole: user.role,
      instituteId,
      action,
      targetType,
      targetId,
      summary,
      createdAt: firestoreTimestamp(now),
    },
  };
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let raw = '';
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function credentialResponse(studentId: string, instituteId: string, tokenHash: string, version: number, enabled: boolean, createdAt: string): Json {
  return { studentId, instituteId, tokenHash, version, enabled, createdAt };
}

function parentAttendanceProjection(record: Json, attendanceDateKey: string, now: string) {
  const studentId = record.studentId as string;
  const classId = record.classId as string;
  const summaryId = `${studentId}_${attendanceDateKey}_${classId}`;
  const departureTime = record.departureTime ?? null;
  const entryTime = record.entryTime ?? null;
  return {
    path: `parent_attendance_summaries/${summaryId}`,
    fields: {
      summaryId,
      studentId,
      instituteId: record.instituteId,
      classId,
      attendanceDate: record.attendanceDate,
      status: record.status,
      entryTime,
      exitTime: departureTime,
      late: record.status === 'late' || (typeof record.lateMinutes === 'number' && record.lateMinutes > 0),
      currentPresenceState: departureTime != null ? 'departed' : entryTime != null ? 'inside' : 'outside',
      updatedAt: firestoreTimestamp(now),
      sourceVersion: Date.now(),
    },
  };
}

async function teacherCanManageStudent(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  studentId: string,
  instituteId: string,
): Promise<boolean> {
  if (user.role !== 'teacher') return true;
  const profile = await firestore.get(`users/${user.uid}`);
  if (!profile || !permission(profile, 'canGenerateQrCodes')) return false;
  const assignments = await firestore.queryAssignments('studentId', studentId);
  for (const assignment of assignments) {
    if (
      field<boolean>(assignment, 'active') !== true ||
      field<string>(assignment, 'instituteId') !== instituteId
    ) continue;
    const classId = field<string>(assignment, 'classId');
    if (!classId || !idPattern.test(classId)) continue;
    const academicClass = await firestore.get(`classes/${classId}`);
    if (academicClass && activeClass(academicClass) && field<unknown[]>(academicClass, 'teacherIds')?.includes(user.uid)) {
      return true;
    }
  }
  return false;
}

async function authorizeStudentQr(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  student: FirestoreDocument,
): Promise<{ studentId: string; instituteId: string }> {
  const studentId = field<string>(student, 'studentId');
  const instituteId = field<string>(student, 'instituteId');
  if (!studentId || !instituteId || field<boolean>(student, 'active') !== true) {
    throw new AppError(404, 'student_unavailable', 'This student is unavailable.');
  }
  if (!activeSuperAdmin(user) && user.instituteId !== instituteId) {
    throw new AppError(403, 'cross_institute', 'This student is outside your institute.');
  }
  if (
    !activeSuperAdmin(user) &&
    user.role !== 'instituteAdmin' &&
    !(await teacherCanManageStudent(firestore, user, studentId, instituteId))
  ) {
    throw new AppError(403, 'forbidden', 'You are not permitted to manage this student QR.');
  }
  return { studentId, instituteId };
}

export async function regenerateQr({ firestore, user, payload }: AttendanceContext): Promise<Json> {
  exact(payload, ['studentId']);
  const studentId = text(payload.studentId, 'studentId');
  if (!idPattern.test(studentId)) throw new AppError(400, 'invalid_payload', 'The studentId is invalid.');
  const student = await firestore.get(`students/${studentId}`);
  if (!student) throw new AppError(404, 'student_unavailable', 'This student is unavailable.');
  const scope = await authorizeStudentQr(firestore, user, student);
  const oldHash = field<string>(student, 'qrTokenHash');
  const currentVersion = field<number>(student, 'qrVersion');
  if (!Number.isInteger(currentVersion) || (currentVersion ?? 0) < 0) {
    throw new AppError(409, 'student_invalid', 'This student QR cannot be updated.');
  }
  const token = randomToken();
  const tokenHash = await safeHash(token);
  const version = (currentVersion ?? 0) + 1;
  const now = new Date().toISOString();
  const writes: Array<{ path: string; fields: Json; createOnly?: boolean; updateTime?: string }> = [
    {
      path: `students/${studentId}`,
      updateTime: student.updateTime,
      fields: {
        ...student.fields,
        qrTokenHash: tokenHash,
        qrVersion: version,
        qrEnabled: true,
        updatedAt: firestoreTimestamp(now),
        updatedBy: user.uid,
      },
    },
    {
      path: `qr_tokens/${tokenHash}`,
      createOnly: true,
      fields: {
        studentId,
        instituteId: scope.instituteId,
        tokenHash,
        version,
        enabled: true,
        createdAt: firestoreTimestamp(now),
        updatedAt: firestoreTimestamp(now),
        updatedBy: user.uid,
      },
    },
  ];
  if (oldHash && hashPattern.test(oldHash)) {
    const oldCredential = await firestore.get(`qr_tokens/${oldHash}`);
    if (oldCredential) {
      writes.push({
        path: `qr_tokens/${oldHash}`,
        updateTime: oldCredential.updateTime,
        fields: { ...oldCredential.fields, enabled: false, revokedAt: firestoreTimestamp(now), updatedAt: firestoreTimestamp(now), updatedBy: user.uid },
      });
    }
  }
  writes.push(audit(user, scope.instituteId, 'studentQrRegenerated', 'qrToken', tokenHash, 'Student QR regenerated and previous credential revoked', now));
  await firestore.commit(writes);
  return {
    payload: `attendiqo://student/${token}`,
    credential: credentialResponse(studentId, scope.instituteId, tokenHash, version, true, now),
  };
}

export async function setQrEnabled({ firestore, user, payload }: AttendanceContext): Promise<Json> {
  exact(payload, ['studentId', 'enabled']);
  const studentId = text(payload.studentId, 'studentId');
  if (!idPattern.test(studentId) || typeof payload.enabled !== 'boolean') {
    throw new AppError(400, 'invalid_payload', 'The QR setting is invalid.');
  }
  const student = await firestore.get(`students/${studentId}`);
  if (!student) throw new AppError(404, 'student_unavailable', 'This student is unavailable.');
  const scope = await authorizeStudentQr(firestore, user, student);
  const tokenHash = field<string>(student, 'qrTokenHash');
  const version = field<number>(student, 'qrVersion');
  if (!tokenHash || !hashPattern.test(tokenHash) || !Number.isInteger(version)) {
    throw new AppError(409, 'qr_unavailable', 'Generate a QR before changing this setting.');
  }
  const credential = await firestore.get(`qr_tokens/${tokenHash}`);
  if (!credential || field<string>(credential, 'studentId') !== studentId || field<number>(credential, 'version') !== version) {
    throw new AppError(409, 'qr_unavailable', 'Generate a new QR before changing this setting.');
  }
  const now = new Date().toISOString();
  await firestore.commit([
    { path: `students/${studentId}`, updateTime: student.updateTime, fields: { ...student.fields, qrEnabled: payload.enabled, updatedAt: firestoreTimestamp(now), updatedBy: user.uid } },
    { path: `qr_tokens/${tokenHash}`, updateTime: credential.updateTime, fields: { ...credential.fields, enabled: payload.enabled, updatedAt: firestoreTimestamp(now), updatedBy: user.uid } },
    audit(user, scope.instituteId, payload.enabled ? 'studentQrEnabled' : 'studentQrDisabled', 'qrToken', tokenHash, payload.enabled ? 'Student QR enabled' : 'Student QR disabled', now),
  ]);
  return { credential: credentialResponse(studentId, scope.instituteId, tokenHash, version as number, payload.enabled, timestamp(field(credential, 'createdAt')) ?? now) };
}

function publicSession(fields: Json): Json {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => {
    if (value && typeof value === 'object' && '__attendiqoFirestoreTimestamp' in (value as Json)) {
      return [key, (value as Json).__attendiqoFirestoreTimestamp];
    }
    return [key, value];
  }));
}

function publicRecord(fields: Json): Json {
  return publicSession(fields);
}

export async function startSession({ firestore, user, payload }: AttendanceContext): Promise<Json> {
  exact(payload, ['classId', 'date', 'scheduleChangeId']);
  const classId = text(payload.classId, 'classId');
  if (!idPattern.test(classId)) throw new AppError(400, 'invalid_payload', 'The classId is invalid.');
  const date = isoDate(payload.date);
  const academicClass = await firestore.get(`classes/${classId}`);
  if (!academicClass) throw new AppError(404, 'class_unavailable', 'This class is unavailable.');
  await authorizeClass(firestore, user, academicClass, 'canTakeAttendance');
  const instituteId = field<string>(academicClass, 'instituteId')!;
  const expectedStartTime = timeValue(field(academicClass, 'startTime'), 'class start time');
  const expectedEndTime = timeValue(field(academicClass, 'endTime'), 'class end time');
  let effectiveStartTime = expectedStartTime;
  let effectiveEndTime = expectedEndTime;
  let scheduleChangeId: string | null = null;
  if (payload.scheduleChangeId != null) {
    scheduleChangeId = text(payload.scheduleChangeId, 'scheduleChangeId');
    if (!idPattern.test(scheduleChangeId)) throw new AppError(400, 'invalid_payload', 'The scheduleChangeId is invalid.');
    const change = await firestore.get(`class_schedule_changes/${scheduleChangeId}`);
    const changeDate = timestamp(field(change ?? { fields: {} }, 'effectiveDate'))?.slice(0, 10);
    if (!change || field<string>(change, 'classId') !== classId || field<string>(change, 'instituteId') !== instituteId || field<string>(change, 'status') !== 'scheduled' || changeDate !== date) {
      throw new AppError(409, 'schedule_change_invalid', 'The class schedule change is unavailable.');
    }
    effectiveStartTime = timeValue(field(change, 'newStartTime'), 'effective start time');
    effectiveEndTime = timeValue(field(change, 'newEndTime'), 'effective end time');
  }
  const sessionId = await safeHash(`${classId}:${date}`);
  const existing = await firestore.get(`attendance_sessions/${sessionId}`);
  if (existing) {
    if (field<string>(existing, 'status') === 'open' && field<string>(existing, 'classId') === classId) {
      return { session: existing.fields };
    }
    throw new AppError(409, 'session_exists', 'Attendance for this class and date is already finished.');
  }
  const assignments = await firestore.queryAssignments('classId', classId);
  const totalStudents = assignments.filter((assignment) => field<boolean>(assignment, 'active') === true && field<string>(assignment, 'status') === 'active' && field<string>(assignment, 'instituteId') === instituteId).length;
  const now = new Date().toISOString();
  const fields: Json = {
    sessionId,
    instituteId,
    classId,
    date: firestoreTimestamp(`${date}T00:00:00.000Z`),
    sessionType: 'entry',
    status: 'open',
    startedAt: firestoreTimestamp(now),
    startedBy: user.uid,
    closedAt: null,
    closedBy: null,
    expectedStartTime,
    expectedEndTime,
    effectiveStartTime,
    effectiveEndTime,
    scheduleChangeId,
    entryModeEnabled: true,
    departureModeEnabled: true,
    totalStudents,
    presentCount: 0,
    lateCount: 0,
    absentCount: 0,
    createdAt: firestoreTimestamp(now),
    updatedAt: firestoreTimestamp(now),
  };
  await firestore.commit([
    { path: `attendance_sessions/${sessionId}`, createOnly: true, fields },
    audit(user, instituteId, 'attendanceSessionStarted', 'attendanceSession', sessionId, 'Attendance session started', now),
  ]);
  return { session: publicSession(fields) };
}

function lateMinutes(now: Date, attendanceDate: string, startTime: string): number {
  // Attendiqo currently serves Sri Lankan institutes. Convert the Worker UTC
  // clock to Asia/Colombo (+05:30) before comparing with the local schedule.
  const localNow = new Date(now.getTime() + 330 * 60 * 1000);
  const scheduled = Date.parse(`${attendanceDate}T${startTime}:00.000Z`);
  return Math.max(0, Math.floor((localNow.getTime() - scheduled) / 60000));
}

async function loadSessionAndClass(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  sessionId: string,
  requiredPermission: 'canTakeAttendance' | 'canCorrectAttendance',
): Promise<{ session: FirestoreDocument; academicClass: FirestoreDocument; instituteId: string; classId: string }> {
  const session = await firestore.get(`attendance_sessions/${sessionId}`);
  const classId = field<string>(session ?? { fields: {} }, 'classId');
  const instituteId = field<string>(session ?? { fields: {} }, 'instituteId');
  if (!session || !classId || !instituteId || !idPattern.test(classId)) {
    throw new AppError(404, 'session_unavailable', 'This attendance session is unavailable.');
  }
  const academicClass = await firestore.get(`classes/${classId}`);
  if (!academicClass || field<string>(academicClass, 'instituteId') !== instituteId) {
    throw new AppError(404, 'class_unavailable', 'This class is unavailable.');
  }
  await authorizeClass(firestore, user, academicClass, requiredPermission);
  return { session, academicClass, instituteId, classId };
}

export async function recordScan({ firestore, user, payload, notify }: AttendanceContext): Promise<Json> {
  exact(payload, ['sessionId', 'tokenHash', 'mode', 'deviceId']);
  const sessionId = text(payload.sessionId, 'sessionId', 256);
  const tokenHash = text(payload.tokenHash, 'tokenHash', 64);
  const mode = text(payload.mode, 'mode', 16);
  const deviceId = text(payload.deviceId, 'deviceId', 160);
  if (!idPattern.test(sessionId) && !hashPattern.test(sessionId)) throw new AppError(400, 'invalid_payload', 'The sessionId is invalid.');
  if (!hashPattern.test(tokenHash) || !['entry', 'departure'].includes(mode)) throw new AppError(400, 'invalid_qr', 'This QR code is invalid.');
  const loaded = await loadSessionAndClass(firestore, user, sessionId, 'canTakeAttendance');
  if (field<string>(loaded.session, 'status') !== 'open') throw new AppError(409, 'closed_session', 'This attendance session is closed.');
  const credential = await firestore.get(`qr_tokens/${tokenHash}`);
  if (!credential) throw new AppError(404, 'invalid_qr', 'This QR code is invalid or has been replaced.');
  if (field<boolean>(credential, 'enabled') !== true) throw new AppError(409, 'disabled_qr', 'This QR code is disabled.');
  if (field<string>(credential, 'instituteId') !== loaded.instituteId) throw new AppError(409, 'wrong_institute', 'This student belongs to another institute.');
  const studentId = field<string>(credential, 'studentId');
  if (!studentId || !idPattern.test(studentId)) throw new AppError(404, 'invalid_qr', 'This QR code is invalid.');
  const student = await firestore.get(`students/${studentId}`);
  if (!student || field<boolean>(student, 'active') !== true || field<string>(student, 'status') !== 'active' || field<boolean>(student, 'qrEnabled') !== true || field<number>(student, 'qrVersion') !== field<number>(credential, 'version') || field<string>(student, 'qrTokenHash') !== tokenHash) {
    throw new AppError(409, 'inactive_student', 'This student or QR code is inactive.');
  }
  const assignment = await firestore.get(`class_students/${loaded.classId}_${studentId}`);
  if (!assignment || field<boolean>(assignment, 'active') !== true || field<string>(assignment, 'status') !== 'active' || field<string>(assignment, 'instituteId') !== loaded.instituteId) {
    throw new AppError(409, 'wrong_class', 'This student is not enrolled in this class.');
  }
  const recordId = `${sessionId}_${studentId}`;
  const existing = await firestore.get(`attendance_records/${recordId}`);
  const now = new Date();
  const nowIso = now.toISOString();
  const attendanceDateKey = timestamp(field(loaded.session, 'date'))?.slice(0, 10);
  if (!attendanceDateKey) throw new AppError(409, 'session_invalid', 'This attendance session is invalid.');
  let record: Json;
  if (mode === 'entry') {
    if (existing && field(existing, 'entryTime') != null) throw new AppError(409, 'duplicate_entry', 'Entry is already recorded.');
    const startTime = field<string>(loaded.session, 'effectiveStartTime');
    if (!startTime || !timePattern.test(startTime)) throw new AppError(409, 'session_invalid', 'This attendance session is invalid.');
    const minutes = lateMinutes(now, attendanceDateKey, startTime);
    record = {
      attendanceRecordId: recordId,
      sessionId,
      instituteId: loaded.instituteId,
      classId: loaded.classId,
      studentId,
      attendanceDate: firestoreTimestamp(`${attendanceDateKey}T00:00:00.000Z`),
      entryTime: firestoreTimestamp(nowIso),
      departureTime: null,
      status: minutes > 0 ? 'late' : 'present',
      lateMinutes: minutes,
      entryMarkedBy: user.uid,
      departureMarkedBy: null,
      entryDeviceId: deviceId,
      departureDeviceId: null,
      scanMethod: 'qr',
      manuallyCorrected: false,
      correctionReason: null,
      correctedBy: null,
      correctedAt: null,
      syncState: 'confirmed',
      createdAt: firestoreTimestamp(nowIso),
      updatedAt: firestoreTimestamp(nowIso),
    };
  } else {
    if (!existing || field(existing, 'entryTime') == null) throw new AppError(409, 'departure_before_entry', 'Record entry before departure.');
    if (field(existing, 'departureTime') != null) throw new AppError(409, 'duplicate_departure', 'Departure is already recorded.');
    record = {
      ...existing.fields,
      departureTime: firestoreTimestamp(nowIso),
      departureMarkedBy: user.uid,
      departureDeviceId: deviceId,
      updatedAt: firestoreTimestamp(nowIso),
    };
  }
  const verifies = [loaded.session, loaded.academicClass, credential, student, assignment]
    .map((document, index) => ({ document, path: [
      `attendance_sessions/${sessionId}`,
      `classes/${loaded.classId}`,
      `qr_tokens/${tokenHash}`,
      `students/${studentId}`,
      `class_students/${loaded.classId}_${studentId}`,
    ][index] }))
    .filter((value): value is { document: FirestoreDocument & { updateTime: string }; path: string } => typeof value.document.updateTime === 'string')
    .map((value) => ({ path: value.path, updateTime: value.document.updateTime }));
  await firestore.commit([
    { path: `attendance_records/${recordId}`, createOnly: !existing, updateTime: existing?.updateTime, fields: record },
    parentAttendanceProjection(record, attendanceDateKey, nowIso),
    audit(user, loaded.instituteId, mode === 'entry' ? 'studentEntryRecorded' : 'studentDepartureRecorded', 'attendanceRecord', recordId, mode === 'entry' ? 'Student entry recorded' : 'Student departure recorded', nowIso),
  ], verifies);
  await notify?.({ studentId, status: String(record.status), mode }).catch(() => undefined);
  return { status: 'accepted', message: mode === 'entry' ? 'Entry recorded.' : 'Departure recorded.', studentId, record: publicRecord(record) };
}

export async function finishSession({ firestore, user, payload, notify }: AttendanceContext, cancelled: boolean): Promise<Json> {
  exact(payload, ['sessionId']);
  const sessionId = text(payload.sessionId, 'sessionId', 256);
  const loaded = await loadSessionAndClass(firestore, user, sessionId, 'canTakeAttendance');
  if (field<string>(loaded.session, 'status') !== 'open') throw new AppError(409, 'closed_session', 'This attendance session is already finished.');
  const now = new Date().toISOString();
  const records = await firestore.queryAttendanceRecords(sessionId);
  const presentCount = records.filter((record) => field<string>(record, 'status') === 'present').length;
  const lateCount = records.filter((record) => field<string>(record, 'status') === 'late').length;
  const existingAbsentCount = records.filter((record) => field<string>(record, 'status') === 'absent').length;
  const assignments = cancelled ? [] : (await firestore.queryAssignments('classId', loaded.classId)).filter(
    (assignment) =>
      field<boolean>(assignment, 'active') === true &&
      field<string>(assignment, 'status') === 'active' &&
      field<string>(assignment, 'instituteId') === loaded.instituteId,
  );
  const totalStudents = cancelled ? (field<number>(loaded.session, 'totalStudents') ?? 0) : assignments.length;
  const recordedStudents = new Set(records.map((record) => field<string>(record, 'studentId')).filter((value): value is string => !!value));
  const date = timestamp(field(loaded.session, 'date'))?.slice(0, 10);
  if (!cancelled && !date) throw new AppError(409, 'session_invalid', 'This attendance session is invalid.');
  const absentWrites = cancelled ? [] : assignments.flatMap((assignment) => {
    const studentId = field<string>(assignment, 'studentId');
    if (!studentId || !idPattern.test(studentId) || recordedStudents.has(studentId)) return [];
    const recordId = `${sessionId}_${studentId}`;
    return [{ path: `attendance_records/${recordId}`, createOnly: true as const, fields: {
      attendanceRecordId: recordId,
      sessionId,
      instituteId: loaded.instituteId,
      classId: loaded.classId,
      studentId,
      attendanceDate: firestoreTimestamp(`${date}T00:00:00.000Z`),
      entryTime: null,
      departureTime: null,
      status: 'absent',
      lateMinutes: 0,
      entryMarkedBy: user.uid,
      departureMarkedBy: null,
      entryDeviceId: 'session-close',
      departureDeviceId: null,
      scanMethod: 'manual',
      manuallyCorrected: false,
      correctionReason: null,
      correctedBy: null,
      correctedAt: null,
      syncState: 'confirmed',
      createdAt: firestoreTimestamp(now),
      updatedAt: firestoreTimestamp(now),
    } }];
  });
  const fields: Json = {
    ...loaded.session.fields,
    status: cancelled ? 'cancelled' : 'closed',
    closedAt: firestoreTimestamp(now),
    closedBy: user.uid,
    presentCount,
    lateCount,
    absentCount: cancelled ? 0 : existingAbsentCount + absentWrites.length,
    updatedAt: firestoreTimestamp(now),
  };
  const absentProjectionWrites = date
    ? absentWrites.map((write) => parentAttendanceProjection(write.fields, date, now))
    : [];
  await firestore.commit([
    { path: `attendance_sessions/${sessionId}`, updateTime: loaded.session.updateTime, fields },
    ...absentWrites,
    ...absentProjectionWrites,
    audit(user, loaded.instituteId, cancelled ? 'attendanceSessionCancelled' : 'attendanceSessionClosed', 'attendanceSession', sessionId, cancelled ? 'Attendance session cancelled' : 'Attendance session closed', now),
  ]);
  if (!cancelled && notify) await Promise.all(absentWrites.map((write) => notify({ studentId: String(write.fields.studentId), status: 'absent' }).catch(() => undefined)));
  return { session: publicSession(fields) };
}

function statusValue(value: unknown): string {
  const result = text(value, 'status', 16);
  if (!statuses.has(result)) throw new AppError(400, 'invalid_payload', 'The attendance status is invalid.');
  return result;
}

function optionalClientTime(value: unknown, fieldName: string): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const result = timestamp(value);
  if (!result) throw new AppError(400, 'invalid_payload', `The ${fieldName} is invalid.`);
  return result;
}

export async function recordManual({ firestore, user, payload, notify }: AttendanceContext): Promise<Json> {
  exact(payload, ['sessionId', 'studentId', 'status', 'reason']);
  const sessionId = text(payload.sessionId, 'sessionId', 256);
  const studentId = text(payload.studentId, 'studentId');
  const status = statusValue(payload.status);
  const reason = text(payload.reason, 'reason', 240);
  const loaded = await loadSessionAndClass(firestore, user, sessionId, 'canCorrectAttendance');
  if (field<string>(loaded.session, 'status') !== 'open') throw new AppError(409, 'closed_session', 'This attendance session is closed.');
  const student = await firestore.get(`students/${studentId}`);
  const assignment = await firestore.get(`class_students/${loaded.classId}_${studentId}`);
  if (!student || field<boolean>(student, 'active') !== true || !assignment || field<boolean>(assignment, 'active') !== true || field<string>(assignment, 'instituteId') !== loaded.instituteId) {
    throw new AppError(409, 'student_ineligible', 'This student is not eligible for this class.');
  }
  const recordId = `${sessionId}_${studentId}`;
  const existing = await firestore.get(`attendance_records/${recordId}`);
  const now = new Date().toISOString();
  const date = timestamp(field(loaded.session, 'date'))?.slice(0, 10);
  if (!date) throw new AppError(409, 'session_invalid', 'This attendance session is invalid.');
  const record: Json = {
    attendanceRecordId: recordId,
    sessionId,
    instituteId: loaded.instituteId,
    classId: loaded.classId,
    studentId,
    attendanceDate: firestoreTimestamp(`${date}T00:00:00.000Z`),
    entryTime: status === 'absent' ? null : firestoreTimestamp(now),
    departureTime: null,
    status,
    lateMinutes: status === 'late' ? 1 : 0,
    entryMarkedBy: user.uid,
    departureMarkedBy: null,
    entryDeviceId: 'manual',
    departureDeviceId: null,
    scanMethod: 'manual',
    manuallyCorrected: true,
    correctionReason: reason,
    correctedBy: user.uid,
    correctedAt: firestoreTimestamp(now),
    syncState: 'confirmed',
    createdAt: existing?.fields.createdAt ?? firestoreTimestamp(now),
    updatedAt: firestoreTimestamp(now),
  };
  await firestore.commit([
    { path: `attendance_records/${recordId}`, createOnly: !existing, updateTime: existing?.updateTime, fields: record },
    parentAttendanceProjection(record, date, now),
    audit(user, loaded.instituteId, 'manualAttendanceRecorded', 'attendanceRecord', recordId, 'Manual attendance recorded with a reason', now),
  ]);
  await notify?.({ studentId, status }).catch(() => undefined);
  return { record: publicRecord(record) };
}

export async function correctRecord({ firestore, user, payload, notify }: AttendanceContext): Promise<Json> {
  exact(payload, ['attendanceRecordId', 'status', 'reason', 'entryTime', 'departureTime']);
  const recordId = text(payload.attendanceRecordId, 'attendanceRecordId', 256);
  const status = statusValue(payload.status);
  const reason = text(payload.reason, 'reason', 240);
  const existing = await firestore.get(`attendance_records/${recordId}`);
  const sessionId = field<string>(existing ?? { fields: {} }, 'sessionId');
  if (!existing || !sessionId) throw new AppError(404, 'record_unavailable', 'This attendance record is unavailable.');
  const loaded = await loadSessionAndClass(firestore, user, sessionId, 'canCorrectAttendance');
  if (field<string>(existing, 'instituteId') !== loaded.instituteId || field<string>(existing, 'classId') !== loaded.classId) {
    throw new AppError(403, 'cross_institute', 'This attendance record is outside your institute.');
  }
  const requestedEntry = optionalClientTime(payload.entryTime, 'entryTime');
  const requestedDeparture = optionalClientTime(payload.departureTime, 'departureTime');
  const now = new Date().toISOString();
  const before = publicRecord(existing.fields);
  const record: Json = {
    ...existing.fields,
    status,
    lateMinutes: status === 'late' ? Math.max(1, field<number>(existing, 'lateMinutes') ?? 1) : 0,
    scanMethod: 'correction',
    manuallyCorrected: true,
    correctionReason: reason,
    correctedBy: user.uid,
    correctedAt: firestoreTimestamp(now),
    updatedAt: firestoreTimestamp(now),
    ...(requestedEntry !== undefined ? { entryTime: requestedEntry === null ? null : firestoreTimestamp(requestedEntry) } : {}),
    ...(requestedDeparture !== undefined ? { departureTime: requestedDeparture === null ? null : firestoreTimestamp(requestedDeparture) } : {}),
  };
  const correctionId = crypto.randomUUID();
  const attendanceDateKey = timestamp(field(existing, 'attendanceDate'))?.slice(0, 10);
  if (!attendanceDateKey) throw new AppError(409, 'record_invalid', 'This attendance record is invalid.');
  await firestore.commit([
    { path: `attendance_records/${recordId}`, updateTime: existing.updateTime, fields: record },
    parentAttendanceProjection(record, attendanceDateKey, now),
    { path: `attendance_corrections/${correctionId}`, createOnly: true, fields: {
      correctionId,
      attendanceRecordId: recordId,
      instituteId: loaded.instituteId,
      classId: loaded.classId,
      studentId: field<string>(existing, 'studentId') ?? '',
      before,
      after: publicRecord(record),
      reason,
      correctedBy: user.uid,
      correctedAt: firestoreTimestamp(now),
    } },
    audit(user, loaded.instituteId, 'attendanceCorrected', 'attendanceRecord', recordId, 'Attendance record corrected with a reason', now),
  ]);
  const correctedStudentId = field<string>(existing, 'studentId');
  if (correctedStudentId) await notify?.({ studentId: correctedStudentId, status }).catch(() => undefined);
  return { record: publicRecord(record) };
}
