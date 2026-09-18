import { AppError, safeHash, type AuthenticatedUser, type FirestoreDocument } from './security';
import { firestoreTimestamp, type WorkerFirestoreAdmin } from './worker-firestore-admin';

type Json = Record<string, unknown>;
type Context = { firestore: WorkerFirestoreAdmin; user: AuthenticatedUser; payload: Json };
const idPattern = /^[A-Za-z0-9_-]{1,128}$/;
const mobilePattern = /^(?:\+947|07)\d{8}$/;

function exact(value: Json, fields: string[]) {
  for (const key of Object.keys(value)) if (!fields.includes(key)) throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
}
function text(value: unknown, field: string, max: number, optional = false): string | undefined {
  if (optional && (value == null || value === '')) return undefined;
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  return value.trim();
}
function boolPermission(profile: FirestoreDocument, name: string): boolean {
  const permissions = profile.fields.permissions;
  return !!permissions && typeof permissions === 'object' && (permissions as Json)[name] === true;
}
async function teacherProfile(ctx: Context, permission: 'canAddStudents' | 'canEditStudents'): Promise<FirestoreDocument> {
  const { firestore, user } = ctx;
  if (user.role !== 'teacher' || !user.active || !user.instituteId) throw new AppError(403, 'forbidden', 'Teacher access is required.');
  const profile = await firestore.get(`users/${user.uid}`);
  if (!profile || profile.fields.active !== true || profile.fields.instituteId !== user.instituteId || !boolPermission(profile, permission) || !boolPermission(profile, 'canViewParentContacts')) {
    throw new AppError(403, 'forbidden', 'The required teacher permissions are not enabled.');
  }
  return profile;
}
async function assignedClassIds(ctx: Context): Promise<Set<string>> {
  const classes = await ctx.firestore.queryClassesByTeacher(ctx.user.uid);
  return new Set(classes.filter((item) => item.fields.active === true && item.fields.status === 'active' && item.fields.instituteId === ctx.user.instituteId).map((item) => item.fields.classId).filter((id): id is string => typeof id === 'string'));
}
async function assignedStudentIds(ctx: Context, classIds: Set<string>): Promise<Set<string>> {
  const assignments = (await Promise.all([...classIds].map((classId) => ctx.firestore.queryAssignments('classId', classId)))).flat();
  return new Set(assignments.filter((item) => item.fields.active === true && item.fields.instituteId === ctx.user.instituteId).map((item) => item.fields.studentId).filter((id): id is string => typeof id === 'string'));
}
function safeStudent(document: FirestoreDocument): Json {
  return { ...document.fields, qrTokenHash: '0'.repeat(64) };
}
export async function listTeacherStudents(ctx: Context): Promise<Json> {
  exact(ctx.payload, []);
  await teacherProfile(ctx, boolPermission(await ctx.firestore.get(`users/${ctx.user.uid}`) ?? { fields: {} }, 'canEditStudents') ? 'canEditStudents' : 'canAddStudents');
  const classIds = await assignedClassIds(ctx);
  const studentIds = await assignedStudentIds(ctx, classIds);
  const students = await Promise.all([...studentIds].map((id) => ctx.firestore.get(`students/${id}`)));
  return { students: students.filter((item): item is FirestoreDocument => !!item && item.fields.active !== false && item.fields.instituteId === ctx.user.instituteId).map(safeStudent) };
}

const editableFields = ['studentId','classId','studentNumber','fullName','preferredName','address','primaryParentName','primaryParentMobile','secondaryParentName','secondaryParentMobile','parentEmail','emergencyContactName','emergencyContactMobile','status','active'];
function normalized(payload: Json) {
  const studentNumber = text(payload.studentNumber, 'studentNumber', 32)!.toUpperCase();
  const primaryParentMobile = text(payload.primaryParentMobile, 'primaryParentMobile', 16)!;
  if (!/^[A-Z0-9][A-Z0-9_-]{1,31}$/.test(studentNumber) || !mobilePattern.test(primaryParentMobile.replaceAll(' ', ''))) throw new AppError(400, 'invalid_payload', 'The student number or parent mobile is invalid.');
  const status = text(payload.status, 'status', 24)!;
  if (!['active','inactive','suspended','leftInstitute'].includes(status) || typeof payload.active !== 'boolean') throw new AppError(400, 'invalid_payload', 'The student status is invalid.');
  return {
    studentNumber, fullName: text(payload.fullName, 'fullName', 160)!, preferredName: text(payload.preferredName, 'preferredName', 100, true) ?? null,
    address: text(payload.address, 'address', 500, true) ?? '', primaryParentName: text(payload.primaryParentName, 'primaryParentName', 160)!, primaryParentMobile: primaryParentMobile.replaceAll(' ', ''),
    secondaryParentName: text(payload.secondaryParentName, 'secondaryParentName', 160, true) ?? null, secondaryParentMobile: text(payload.secondaryParentMobile, 'secondaryParentMobile', 16, true) ?? null,
    parentEmail: text(payload.parentEmail, 'parentEmail', 254, true)?.toLowerCase() ?? null, emergencyContactName: text(payload.emergencyContactName, 'emergencyContactName', 160, true) ?? null,
    emergencyContactMobile: text(payload.emergencyContactMobile, 'emergencyContactMobile', 16, true) ?? null, status, active: payload.active as boolean,
  };
}
function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32)); let raw = ''; for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
function audit(user: AuthenticatedUser, instituteId: string, action: string, studentId: string, now: string) {
  const auditLogId = crypto.randomUUID();
  return { path: `audit_logs/${auditLogId}`, createOnly: true as const, fields: { auditLogId, actorUid: user.uid, actorRole: user.role, instituteId, action, targetType: 'student', targetId: studentId, summary: action === 'studentCreated' ? 'Teacher created assigned student' : 'Teacher updated assigned student', createdAt: firestoreTimestamp(now) } };
}
export async function createTeacherStudent(ctx: Context): Promise<Json> {
  exact(ctx.payload, editableFields); const profile = await teacherProfile(ctx, 'canAddStudents');
  const classId = text(ctx.payload.classId, 'classId', 128)!; if (!idPattern.test(classId) || !(await assignedClassIds(ctx)).has(classId)) throw new AppError(403, 'forbidden', 'Select a class assigned to you.');
  const data = normalized(ctx.payload); const instituteId = ctx.user.instituteId!;
  const reservationId = `${instituteId}_${data.studentNumber}`; if (await ctx.firestore.get(`student_numbers/${reservationId}`)) throw new AppError(409, 'duplicate_student_number', 'That student number is already in use.');
  const studentId = `student-${crypto.randomUUID()}`; const now = new Date().toISOString(); const token = randomToken(); const tokenHash = await safeHash(token);
  const student = { studentId, instituteId, ...data, dateOfBirth: null, gender: null, qrTokenHash: tokenHash, qrVersion: 1, qrEnabled: true, createdAt: firestoreTimestamp(now), createdBy: ctx.user.uid, updatedAt: firestoreTimestamp(now), updatedBy: ctx.user.uid };
  const assignmentId = `${classId}_${studentId}`;
  await ctx.firestore.commit([
    { path: `student_numbers/${reservationId}`, createOnly: true, fields: { instituteId, studentNumber: data.studentNumber, studentId, createdAt: firestoreTimestamp(now), createdBy: ctx.user.uid } },
    { path: `students/${studentId}`, createOnly: true, fields: student },
    { path: `class_students/${assignmentId}`, createOnly: true, fields: { assignmentId, instituteId, classId, studentId, active: true, joinedAt: firestoreTimestamp(now), joinedBy: ctx.user.uid, leftAt: null, leftBy: null, status: 'active', scheduleOverlapConfirmed: false, scheduleOverlapReason: null, scheduleOverlapConfirmedBy: null, scheduleOverlapConfirmedAt: null } },
    audit(ctx.user, instituteId, 'studentCreated', studentId, now),
  ]);
  return {
    student: { ...student, createdAt: now, updatedAt: now, qrTokenHash: '0'.repeat(64) },
    ...(boolPermission(profile, 'canGenerateQrCodes') ? { qrPayload: `attendiqo://student/${token}` } : {}),
  };
}
export async function updateTeacherStudent(ctx: Context): Promise<Json> {
  exact(ctx.payload, editableFields); await teacherProfile(ctx, 'canEditStudents');
  const studentId = text(ctx.payload.studentId, 'studentId', 128)!; if (!idPattern.test(studentId)) throw new AppError(400, 'invalid_payload', 'The student is invalid.');
  const classIds = await assignedClassIds(ctx); const studentIds = await assignedStudentIds(ctx, classIds); if (!studentIds.has(studentId)) throw new AppError(403, 'forbidden', 'You may edit only students assigned to your classes.');
  const current = await ctx.firestore.get(`students/${studentId}`); if (!current || current.fields.instituteId !== ctx.user.instituteId) throw new AppError(404, 'not_found', 'The student was not found.');
  const data = normalized(ctx.payload); if (data.studentNumber !== current.fields.studentNumber) throw new AppError(409, 'immutable_field', 'The student number cannot be changed.');
  const now = new Date().toISOString(); const student = { ...current.fields, ...data, studentId, instituteId: ctx.user.instituteId!, updatedAt: firestoreTimestamp(now), updatedBy: ctx.user.uid };
  await ctx.firestore.commit([{ path: `students/${studentId}`, updateTime: current.updateTime, fields: student }, audit(ctx.user, ctx.user.instituteId!, 'studentUpdated', studentId, now)]);
  return { student: { ...student, createdAt: current.fields.createdAt, updatedAt: now, qrTokenHash: '0'.repeat(64) } };
}
