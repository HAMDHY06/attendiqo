import { AppError, normalizeSriLankanMobile, type AuthenticatedUser } from './security';
import { firestoreTimestamp, type WorkerFirestoreAdmin } from './worker-firestore-admin';
import type { WorkerIdentityAdmin } from './worker-identity-admin';

type Json = Record<string, unknown>;
type AccountContext = { firestore: WorkerFirestoreAdmin; identity: WorkerIdentityAdmin; user: AuthenticatedUser; payload: Json };

const idPattern = /^[A-Za-z0-9_-]{1,128}$/;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const employeePattern = /^[A-Z0-9][A-Z0-9_-]{1,31}$/;
const permissionNames = [
  'canCreateClasses', 'canEditClasses', 'canAddStudents', 'canEditStudents',
  'canGenerateQrCodes', 'canTakeAttendance', 'canCorrectAttendance',
  'canExportReports', 'canViewParentContacts', 'canSendManualNotifications',
] as const;

function exact(payload: Json, allowed: string[]) {
  if (Object.keys(payload).some((key) => !allowed.includes(key))) throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
}

function text(value: unknown, field: string, max = 160): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  return value.trim();
}

function optionalText(value: unknown, field: string, max = 160): string | null {
  if (value == null || value === '') return null;
  return text(value, field, max);
}

function email(value: unknown): string {
  const result = text(value, 'email', 254).toLowerCase();
  if (!emailPattern.test(result)) throw new AppError(400, 'invalid_email', 'Enter a valid email address.');
  return result;
}

function permissions(value: unknown): Json {
  if (!value || Array.isArray(value) || typeof value !== 'object') throw new AppError(400, 'invalid_permissions', 'Teacher permissions are invalid.');
  const map = value as Json;
  if (Object.keys(map).length !== permissionNames.length || permissionNames.some((name) => typeof map[name] !== 'boolean')) {
    throw new AppError(400, 'invalid_permissions', 'Teacher permissions are invalid.');
  }
  return Object.fromEntries(permissionNames.map((name) => [name, map[name]]));
}

function temporaryPassword(): string {
  const groups = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#%'];
  const all = groups.join('');
  const values = [...groups.map((group) => group[crypto.getRandomValues(new Uint32Array(1))[0] % group.length])];
  while (values.length < 16) values.push(all[crypto.getRandomValues(new Uint32Array(1))[0] % all.length]);
  for (let index = values.length - 1; index > 0; index--) {
    const swap = crypto.getRandomValues(new Uint32Array(1))[0] % (index + 1);
    [values[index], values[swap]] = [values[swap], values[index]];
  }
  return values.join('');
}

function uid(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().replaceAll('-', '')}`;
}

function audit(actor: AuthenticatedUser, instituteId: string, action: string, targetType: string, targetId: string, summary: string, now: string) {
  const auditLogId = uid('audit');
  return { path: `audit_logs/${auditLogId}`, fields: { auditLogId, actorUid: actor.uid, actorRole: actor.role, instituteId, action, targetType, targetId, summary, createdAt: firestoreTimestamp(now) } };
}

async function activeInstitute(firestore: WorkerFirestoreAdmin, instituteId: string) {
  if (!idPattern.test(instituteId)) throw new AppError(400, 'invalid_institute', 'The institute is invalid.');
  const institute = await firestore.get(`institutes/${instituteId}`);
  if (!institute || institute.fields.active !== true || institute.fields.status !== 'active') throw new AppError(409, 'institute_inactive', 'The institute is not active.');
  return institute;
}

async function createScopedAccount(context: AccountContext, role: 'teacher' | 'instituteAdmin'): Promise<Json> {
  const allowed = role === 'teacher'
    ? ['instituteId', 'email', 'displayName', 'phoneNumber', 'employeeNumber', 'permissions']
    : ['instituteId', 'email', 'displayName'];
  exact(context.payload, allowed);
  const requestedInstituteId = text(context.payload.instituteId, 'instituteId', 128);
  if (role === 'instituteAdmin') {
    if (context.user.role !== 'superAdmin' || !context.user.superAdmin) throw new AppError(403, 'forbidden', 'Only a verified Super Admin can create an Institute Admin.');
  } else if (!(
    (context.user.role === 'superAdmin' && context.user.superAdmin) ||
    (context.user.role === 'instituteAdmin' && context.user.instituteId === requestedInstituteId)
  )) throw new AppError(403, 'forbidden', 'You are not permitted to create this teacher.');
  await activeInstitute(context.firestore, requestedInstituteId);
  const accountEmail = email(context.payload.email);
  const displayName = text(context.payload.displayName, 'display name');
  const phoneNumber = role === 'teacher' ? optionalText(context.payload.phoneNumber, 'phone number', 32) : null;
  const employeeNumber = role === 'teacher' ? optionalText(context.payload.employeeNumber, 'employee number', 32)?.toUpperCase() ?? null : null;
  if (employeeNumber && !employeePattern.test(employeeNumber)) throw new AppError(400, 'invalid_employee_number', 'The employee number is invalid.');
  const teacherPermissions = role === 'teacher' ? permissions(context.payload.permissions) : null;
  if (employeeNumber && await context.firestore.get(`teacher_employee_numbers/${requestedInstituteId}_${employeeNumber}`)) {
    throw new AppError(409, 'duplicate_employee_number', 'That employee number is already used in this institute.');
  }
  const accountUid = uid(role === 'teacher' ? 'teacher' : 'admin');
  const password = temporaryPassword();
  const now = new Date().toISOString();
  await context.identity.createUser({ uid: accountUid, email: accountEmail, password, displayName });
  try {
    await context.identity.setClaims(accountUid, { role, instituteId: requestedInstituteId });
    const profile: Json = {
      uid: accountUid, email: accountEmail, displayName, role, instituteId: requestedInstituteId,
      active: true, mustChangePassword: true, createdAt: firestoreTimestamp(now), createdBy: context.user.uid,
      updatedAt: firestoreTimestamp(now), lastLoginAt: null,
    };
    if (role === 'teacher') Object.assign(profile, {
      updatedBy: context.user.uid, phoneNumber, employeeNumber, permissions: teacherPermissions, status: 'pendingFirstLogin',
    });
    const membershipId = `${accountUid}_${requestedInstituteId}`;
    const writes: Array<{ path: string; fields: Json; createOnly?: boolean }> = [
      { path: `users/${accountUid}`, fields: profile, createOnly: true },
      { path: `institute_memberships/${membershipId}`, createOnly: true, fields: {
        uid: accountUid, instituteId: requestedInstituteId, role, status: 'active', requestedAt: firestoreTimestamp(now),
        approvedAt: firestoreTimestamp(now), approvedBy: context.user.uid, reviewedAt: firestoreTimestamp(now), reviewedBy: context.user.uid, updatedAt: firestoreTimestamp(now),
      } },
      audit(context.user, requestedInstituteId, role === 'teacher' ? 'teacherCreated' : 'instituteAdminCreated', role === 'teacher' ? 'teacher' : 'user', accountUid, role === 'teacher' ? 'Teacher account created' : 'Institute Admin account created', now),
    ];
    if (role === 'teacher' && employeeNumber) writes.push({ path: `teacher_employee_numbers/${requestedInstituteId}_${employeeNumber}`, createOnly: true, fields: { instituteId: requestedInstituteId, employeeNumber, teacherUid: accountUid, createdAt: firestoreTimestamp(now), createdBy: context.user.uid } });
    await context.firestore.commit(writes);
  } catch (error) {
    await context.identity.deleteUser(accountUid).catch(() => undefined);
    throw error;
  }
  return { uid: accountUid, email: accountEmail, displayName, instituteId: requestedInstituteId, role, phoneNumber, employeeNumber, permissions: teacherPermissions, createdAt: now, temporaryPassword: password };
}

export const createTeacherAccount = (context: AccountContext) => createScopedAccount(context, 'teacher');
export const createInstituteAdminAccount = (context: AccountContext) => createScopedAccount(context, 'instituteAdmin');

export async function disableInstituteAdmin(context: AccountContext): Promise<Json> {
  exact(context.payload, ['uid', 'instituteId']);
  if (context.user.role !== 'superAdmin' || !context.user.superAdmin) throw new AppError(403, 'forbidden', 'Only a verified Super Admin can disable an Institute Admin.');
  const accountUid = text(context.payload.uid, 'uid', 128);
  const instituteId = text(context.payload.instituteId, 'instituteId', 128);
  const profile = await context.firestore.get(`users/${accountUid}`);
  const membershipId = `${accountUid}_${instituteId}`;
  const membership = await context.firestore.get(`institute_memberships/${membershipId}`);
  if (!profile || profile.fields.role !== 'instituteAdmin' || profile.fields.instituteId !== instituteId || !membership) throw new AppError(404, 'account_unavailable', 'The Institute Admin account was not found.');
  const now = new Date().toISOString();
  await context.identity.setDisabled(accountUid, true);
  try {
    await context.firestore.commit([
      { path: `users/${accountUid}`, updateTime: profile.updateTime, fields: { ...profile.fields, active: false, updatedAt: firestoreTimestamp(now) } },
      { path: `institute_memberships/${membershipId}`, updateTime: membership.updateTime, fields: { ...membership.fields, status: 'suspended', updatedAt: firestoreTimestamp(now), reviewedAt: firestoreTimestamp(now), reviewedBy: context.user.uid } },
      audit(context.user, instituteId, 'instituteAdminDisabled', 'user', accountUid, 'Institute Admin account disabled', now),
    ]);
  } catch (error) {
    await context.identity.setDisabled(accountUid, false).catch(() => undefined);
    throw error;
  }
  return { status: 'disabled' };
}

export async function bootstrapParent(
  firestore: WorkerFirestoreAdmin,
  identity: { uid: string; email?: string },
  payload: Json,
): Promise<Json> {
  exact(payload, ['displayName', 'mobileNumber']);
  if (!identity.email || !emailPattern.test(identity.email)) throw new AppError(400, 'invalid_email', 'The signed-in email is invalid.');
  const displayName = text(payload.displayName, 'display name');
  const mobileNumber = normalizeSriLankanMobile(payload.mobileNumber);
  const now = new Date().toISOString();
  const existing = await firestore.get(`users/${identity.uid}`);
  if (existing) {
    if (existing.fields.role !== 'parent' || existing.fields.email !== identity.email) throw new AppError(409, 'profile_conflict', 'This account cannot be registered as a parent.');
    return { status: 'ready' };
  }
  await firestore.commit([{ path: `users/${identity.uid}`, createOnly: true, fields: {
    uid: identity.uid, email: identity.email.toLowerCase(), displayName, role: 'parent', instituteId: null,
    active: true, mustChangePassword: false, phoneNumber: mobileNumber, parentLinkedStudentIds: [],
    createdAt: firestoreTimestamp(now), createdBy: identity.uid, updatedAt: firestoreTimestamp(now), lastLoginAt: null,
  } }]);
  return { status: 'ready' };
}

export async function linkParentStudent(firestore: WorkerFirestoreAdmin, user: AuthenticatedUser, payload: Json): Promise<Json> {
  exact(payload, ['studentNumber']);
  if (user.role !== 'parent' || !user.instituteId) throw new AppError(403, 'forbidden', 'An active parent membership is required.');
  const studentNumber = text(payload.studentNumber, 'student number', 40).toUpperCase();
  const parent = await firestore.get(`users/${user.uid}`);
  const parentMobile = typeof parent?.fields.phoneNumber === 'string' ? normalizeSriLankanMobile(parent.fields.phoneNumber) : null;
  if (!parentMobile) throw new AppError(409, 'mobile_required', 'Add a valid parent mobile number before linking a child.');
  const students = await firestore.queryStudentsByInstitute(user.instituteId);
  const student = students.find((item) => item.fields.studentNumber === studentNumber && item.fields.active === true && item.fields.status === 'active');
  if (!student || typeof student.fields.studentId !== 'string') throw new AppError(404, 'student_unavailable', 'No active student matches that number.');
  const sourceMobiles = [student.fields.primaryParentMobile, student.fields.secondaryParentMobile]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => { try { return normalizeSriLankanMobile(value); } catch { return ''; } });
  if (!sourceMobiles.includes(parentMobile)) throw new AppError(403, 'parent_not_verified', 'The registered parent mobile number does not match this student. Contact the institute.');
  const studentId = student.fields.studentId;
  const assignments = (await firestore.queryAssignments('studentId', studentId)).filter((item) => item.fields.active === true && item.fields.status === 'active' && item.fields.instituteId === user.instituteId);
  const classIds = assignments.map((item) => item.fields.classId).filter((value): value is string => typeof value === 'string' && idPattern.test(value));
  const classes = (await Promise.all(classIds.map((classId) => firestore.get(`classes/${classId}`)))).filter((item): item is NonNullable<typeof item> => !!item && item.fields.active === true && item.fields.status !== 'archived');
  const existingLinks = await firestore.queryParentLinks(user.uid);
  const activeStudentIds = [...new Set(existingLinks.filter((item) => item.fields.active === true).map((item) => item.fields.studentId).filter((value): value is string => typeof value === 'string').concat(studentId))].sort();
  const activeClassIds = [...new Set(existingLinks.filter((item) => item.fields.active === true).flatMap((item) => Array.isArray(item.fields.classIds) ? item.fields.classIds.filter((value): value is string => typeof value === 'string') : []).concat(classIds))].sort();
  const now = new Date().toISOString();
  const version = Date.now();
  const linkId = `${user.uid}_${studentId}`;
  const existingLink = await firestore.get(`parent_student_links/${linkId}`);
  const writes: Array<{ path: string; fields: Json; createOnly?: boolean; updateTime?: string }> = [
    { path: `parent_student_links/${linkId}`, updateTime: existingLink?.updateTime, fields: {
      parentUid: user.uid, studentId, instituteId: user.instituteId, relationship: 'parent', active: true,
      createdAt: existingLink?.fields.createdAt ?? firestoreTimestamp(now), updatedAt: firestoreTimestamp(now), createdBy: user.uid,
      revokedAt: null, revokedBy: null, sourceVersion: version, classIds,
    } },
    { path: `parent_student_profiles/${studentId}`, fields: {
      studentId, instituteId: user.instituteId, fullName: student.fields.fullName, studentNumber,
      grade: student.fields.grade ?? null, active: true, classIds, publicProfileImageUrl: null, updatedAt: firestoreTimestamp(now), sourceVersion: version,
    } },
    { path: `parent_access_scopes/${user.uid}`, fields: { parentUid: user.uid, active: true, studentIds: activeStudentIds, classIds: activeClassIds, instituteIds: [user.instituteId], updatedAt: firestoreTimestamp(now), sourceVersion: version } },
    { path: `users/${user.uid}`, updateTime: parent?.updateTime, fields: { ...parent!.fields, parentLinkedStudentIds: activeStudentIds, updatedAt: firestoreTimestamp(now) } },
  ];
  for (const academicClass of classes) {
    const classId = academicClass.fields.classId as string;
    const teacherId = academicClass.fields.primaryTeacherId;
    const teacher = typeof teacherId === 'string' ? await firestore.get(`users/${teacherId}`) : undefined;
    writes.push({ path: `parent_class_profiles/${classId}`, fields: {
      classId, instituteId: user.instituteId, className: academicClass.fields.name, subject: academicClass.fields.subject,
      grade: academicClass.fields.grade ?? null, teacherDisplayName: teacher?.fields.displayName ?? null,
      room: academicClass.fields.roomOrLocation ?? null,
      normalSchedule: { daysOfWeek: academicClass.fields.daysOfWeek ?? [], startTime: academicClass.fields.startTime, endTime: academicClass.fields.endTime },
      effectiveSchedule: null, active: true, updatedAt: firestoreTimestamp(now), sourceVersion: version,
    } });
  }
  await firestore.commit(writes);
  return { status: 'linked', studentId };
}
