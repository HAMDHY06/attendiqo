import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  collection,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  runTransaction,
} from 'firebase/firestore';

const projectId = 'attendiqo-system';
let environment;

const teacherPermissions = {
  canCreateClasses: false, canEditClasses: false, canAddStudents: true,
  canEditStudents: true, canGenerateQrCodes: true, canTakeAttendance: true,
  canCorrectAttendance: false, canExportReports: true,
  canViewParentContacts: true, canSendManualNotifications: false,
};

const profile = ({ uid, role, instituteId = null, active = true, mustChangePassword = false }) => ({
  uid,
  email: `${uid}@example.com`,
  displayName: uid,
  role,
  instituteId,
  active,
  mustChangePassword,
  createdAt: new Date('2026-08-01T00:00:00Z'),
  createdBy: 'rules-test',
  updatedAt: new Date('2026-08-01T00:00:00Z'),
  updatedBy: 'rules-test',
  lastLoginAt: null,
  ...(role === 'teacher' ? {
    phoneNumber: null,
    employeeNumber: uid === 'teacher-a' ? 'EMP-A' : null,
    permissions: teacherPermissions,
    status: !active ? 'disabled' : mustChangePassword ? 'pendingFirstLogin' : 'active',
  } : {}),
});

const institute = (id, code, status = 'active') => ({
  instituteId: id,
  instituteCode: code,
  name: `Institute ${code}`,
  address: 'Colombo',
  contactNumber: '+94771234567',
  email: `${code.toLowerCase()}@example.com`,
  active: status === 'active',
  status,
  pushNotificationsEnabled: true,
  smsEnabled: false,
  smsMonthlyLimit: 0,
  allowPaidExtraSms: false,
  smsUsedThisMonth: 0,
  createdAt: new Date('2026-08-01T00:00:00Z'),
  createdBy: 'real-super',
  updatedAt: new Date('2026-08-01T00:00:00Z'),
  updatedBy: 'real-super',
});

const academicClass = ({ id = 'class-a', instituteId = 'institute-a', teacherIds = ['teacher-a'], code = 'MATH-A' } = {}) => ({
  classId: id, instituteId, classCode: code, name: 'Mathematics A', subject: 'Mathematics', description: '',
  grade: '10', primaryTeacherId: teacherIds[0] ?? null, teacherIds,
  daysOfWeek: ['monday', 'wednesday'], startTime: '08:00', endTime: '09:00',
  roomOrLocation: 'Room 1', academicYear: 2026, active: true, status: 'active',
  createdAt: new Date('2026-08-01T00:00:00Z'), createdBy: 'admin-a',
  updatedAt: new Date('2026-08-01T00:00:00Z'), updatedBy: 'admin-a',
});

const student = ({ id = 'student-a', instituteId = 'institute-a', number = 'STU-A' } = {}) => ({
  studentId: id, instituteId, studentNumber: number, fullName: 'Student A', preferredName: null,
  dateOfBirth: null, gender: null, address: '', primaryParentName: 'Parent A',
  primaryParentMobile: '+94771234567', secondaryParentName: null, secondaryParentMobile: null,
  parentEmail: null, emergencyContactName: null, emergencyContactMobile: null,
  status: 'active', active: true, qrTokenHash: 'a'.repeat(64), qrVersion: 1, qrEnabled: true,
  createdAt: new Date('2026-08-01T00:00:00Z'), createdBy: 'admin-a',
  updatedAt: new Date('2026-08-01T00:00:00Z'), updatedBy: 'admin-a',
});

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const records = [
      { ...profile({ uid: 'parent-a', role: 'parent' }), parentLinkedStudentIds: ['student-a'] },
      profile({ uid: 'parent-b', role: 'parent' }),
      profile({ uid: 'inactive-parent', role: 'parent', active: false }),
      profile({ uid: 'teacher-a', role: 'teacher', instituteId: 'institute-a' }),
      profile({ uid: 'teacher-b', role: 'teacher', instituteId: 'institute-b' }),
      profile({ uid: 'inactive-teacher', role: 'teacher', instituteId: 'institute-a', active: false }),
      profile({ uid: 'temporary-teacher', role: 'teacher', instituteId: 'institute-a', mustChangePassword: true }),
      profile({ uid: 'admin-a', role: 'instituteAdmin', instituteId: 'institute-a' }),
      profile({ uid: 'admin-b', role: 'instituteAdmin', instituteId: 'institute-b' }),
      profile({ uid: 'inactive-admin', role: 'instituteAdmin', instituteId: 'institute-a', active: false }),
      profile({ uid: 'fake-super', role: 'superAdmin' }),
      profile({ uid: 'real-super', role: 'superAdmin' }),
      profile({ uid: 'inactive-super', role: 'superAdmin', active: false }),
    ];
    for (const record of records) {
      await setDoc(doc(db, 'users', record.uid), record);
    }
    await setDoc(doc(db, 'institutes', 'institute-a'), institute('institute-a', 'INSTA'));
    await setDoc(doc(db, 'institutes', 'institute-b'), institute('institute-b', 'INSTB'));
    await setDoc(doc(db, 'institutes', 'institute-suspended'), institute('institute-suspended', 'INSTS', 'suspended'));
    await setDoc(doc(db, 'users', 'admin-suspended'), profile({ uid: 'admin-suspended', role: 'instituteAdmin', instituteId: 'institute-suspended' }));
    await setDoc(doc(db, 'institute_codes', 'INSTA'), {
      instituteId: 'institute-a', createdAt: new Date(), createdBy: 'real-super',
    });
    await setDoc(doc(db, 'sms_usage', 'institute-a'), {
      instituteId: 'institute-a', month: '2026-08', used: 7,
    });
    await setDoc(doc(db, 'teacher_employee_numbers', 'institute-a_EMP-A'), {
      instituteId: 'institute-a', employeeNumber: 'EMP-A', teacherUid: 'teacher-a',
      createdAt: new Date(), createdBy: 'rules-test',
    });
    await setDoc(doc(db, 'classes', 'class-a'), academicClass());
    await setDoc(doc(db, 'classes', 'class-b'), academicClass({ id: 'class-b', instituteId: 'institute-b', teacherIds: ['teacher-b'], code: 'MATH-B' }));
    await setDoc(doc(db, 'students', 'student-a'), student());
    await setDoc(doc(db, 'students', 'student-b'), student({ id: 'student-b', instituteId: 'institute-b', number: 'STU-B' }));
    await setDoc(doc(db, 'class_students', 'class-a_student-a'), {
      assignmentId: 'class-a_student-a', instituteId: 'institute-a', classId: 'class-a', studentId: 'student-a',
      active: true, joinedAt: new Date(), joinedBy: 'admin-a', leftAt: null, leftBy: null, status: 'active',
      scheduleOverlapConfirmed: false, scheduleOverlapReason: null,
      scheduleOverlapConfirmedBy: null, scheduleOverlapConfirmedAt: null,
    });
    await setDoc(doc(db, 'parent_student_links', 'parent-a_student-a'), {
      parentUid: 'parent-a', studentId: 'student-a', instituteId: 'institute-a',
      relationship: 'parent', active: true, createdAt: new Date(), updatedAt: new Date(),
      createdBy: 'admin-a', revokedAt: null, revokedBy: null, sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_student_links', 'parent-b_student-b'), {
      parentUid: 'parent-b', studentId: 'student-b', instituteId: 'institute-b',
      relationship: 'parent', active: false, createdAt: new Date(), updatedAt: new Date(),
      createdBy: 'admin-b', revokedAt: new Date(), revokedBy: 'admin-b', sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_student_links', 'parent-a_student-b'), {
      parentUid: 'parent-a', studentId: 'student-b', instituteId: 'institute-a',
      relationship: 'parent', active: false, createdAt: new Date(), updatedAt: new Date(),
      createdBy: 'admin-a', revokedAt: new Date(), revokedBy: 'admin-a', sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_access_scopes', 'parent-a'), {
      parentUid: 'parent-a', active: true, studentIds: ['student-a'],
      classIds: ['class-a'], instituteIds: ['institute-a'], updatedAt: new Date(),
    });
    await setDoc(doc(db, 'parent_access_scopes', 'inactive-parent'), {
      parentUid: 'inactive-parent', active: true, studentIds: ['student-a'],
      classIds: ['class-a'], instituteIds: ['institute-a'], updatedAt: new Date(),
    });
    await setDoc(doc(db, 'parent_student_profiles', 'student-a'), {
      studentId: 'student-a', instituteId: 'institute-a', fullName: 'Student A',
      studentNumber: 'STU-A', grade: '10', active: true, classIds: ['class-a'],
      publicProfileImageUrl: null, updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_student_profiles', 'student-b'), {
      studentId: 'student-b', instituteId: 'institute-b', fullName: 'Student B',
      studentNumber: 'STU-B', grade: '10', active: true, classIds: ['class-b'],
      publicProfileImageUrl: null, updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_class_profiles', 'class-a'), {
      classId: 'class-a', instituteId: 'institute-a', className: 'Math A', subject: 'Math',
      grade: '10', teacherDisplayName: 'Teacher A', room: 'Room 1',
      normalSchedule: {}, effectiveSchedule: null, active: true, updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_class_profiles', 'class-b'), {
      classId: 'class-b', instituteId: 'institute-b', className: 'Math B', subject: 'Math',
      grade: '10', teacherDisplayName: 'Teacher B', room: 'Room 2',
      normalSchedule: {}, effectiveSchedule: null, active: true, updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_attendance_summaries', 'student-a_2026-08-01_class-a'), {
      summaryId: 'student-a_2026-08-01_class-a', studentId: 'student-a',
      instituteId: 'institute-a', classId: 'class-a', attendanceDate: new Date('2026-08-01'),
      status: 'present', entryTime: new Date(), exitTime: null, late: false,
      currentPresenceState: 'inside', updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_attendance_summaries', 'student-b_2026-08-01_class-b'), {
      summaryId: 'student-b_2026-08-01_class-b', studentId: 'student-b',
      instituteId: 'institute-b', classId: 'class-b', attendanceDate: new Date('2026-08-01'),
      status: 'present', entryTime: new Date(), exitTime: null, late: false,
      currentPresenceState: 'inside', updatedAt: new Date(), sourceVersion: 1,
    });
    const future = new Date('2099-01-01T00:00:00Z');
    const past = new Date('2020-01-01T00:00:00Z');
    for (const [id, targetType, students, classes, active, expiresAt, instituteId = 'institute-a'] of [
      ['notice-institute', 'instituteParents', [], [], true, future],
      ['notice-student', 'student', ['student-a'], [], true, future],
      ['notice-class', 'class', [], ['class-a'], true, future],
      ['notice-unrelated', 'student', ['student-b'], [], true, future, 'institute-b'],
      ['notice-inactive', 'instituteParents', [], [], false, future],
      ['notice-expired', 'instituteParents', [], [], true, past],
    ]) await setDoc(doc(db, 'parent_notices', id), {
      noticeId: id, instituteId, title: id, message: 'Safe parent notice', priority: 'normal',
      publishedAt: new Date(), expiresAt, active, targetType,
      targetStudentIds: students, targetClassIds: classes, updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'parent_notices', 'notice-future-published'), {
      noticeId: 'notice-future-published', instituteId: 'institute-a',
      title: 'Future notice', message: 'Not published yet', priority: 'normal',
      publishedAt: future, expiresAt: null, active: true,
      targetType: 'instituteParents', targetStudentIds: [], targetClassIds: [],
      updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'institute_public_profiles', 'institute-a'), {
      instituteId: 'institute-a', displayName: 'Institute A', logoUrl: null,
      publicPhone: null, publicEmail: null, publicAddress: null,
      status: 'active', updatedAt: new Date(), sourceVersion: 1,
    });
    await setDoc(doc(db, 'institute_public_profiles', 'institute-b'), {
      instituteId: 'institute-b', displayName: 'Institute B', logoUrl: null,
      publicPhone: null, publicEmail: null, publicAddress: null,
      status: 'active', updatedAt: new Date(), sourceVersion: 1,
    });
  });
});

after(async () => environment.cleanup());

const superDb = () => environment.authenticatedContext('real-super', { superAdmin: true }).firestore();

async function createInstitute(db, id = 'institute-c', code = 'INSTC') {
  const batch = writeBatch(db);
  batch.set(doc(db, 'institute_codes', code), {
    instituteId: id,
    createdAt: serverTimestamp(),
    createdBy: 'real-super',
  });
  batch.set(doc(db, 'institutes', id), {
    ...institute(id, code),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

test('unauthenticated users cannot read profiles', async () => {
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'users', 'teacher-a')));
});

test('user can read own profile', async () => {
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-a')));
});

test('user cannot change own role, institute, or active state', async () => {
  const own = doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-a');
  await assertFails(updateDoc(own, { role: 'superAdmin' }));
  await assertFails(updateDoc(own, { instituteId: 'institute-b' }));
  const inactive = doc(environment.authenticatedContext('inactive-teacher').firestore(), 'users', 'inactive-teacher');
  await assertFails(updateDoc(inactive, { active: true }));
  const parent = doc(
    environment.authenticatedContext('parent-a').firestore(),
    'users',
    'parent-a',
  );
  await assertFails(updateDoc(parent, {
    parentLinkedStudentIds: ['student-b'],
  }));
});

test('teacher first login atomically clears password flag, activates status, and audits', async () => {
  const db = environment.authenticatedContext('temporary-teacher').firestore();
  const batch = writeBatch(db);
  batch.update(doc(db, 'users', 'temporary-teacher'), {
    mustChangePassword: false,
    status: 'active',
    updatedBy: 'temporary-teacher',
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'audit_logs', 'first-login'), {
    auditLogId: 'first-login', actorUid: 'temporary-teacher', actorRole: 'teacher',
    instituteId: 'institute-a', action: 'teacherFirstLoginCompleted', targetType: 'teacher',
    targetId: 'temporary-teacher', summary: 'Teacher completed required first-login password change',
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
});

test('parent cannot access a teacher profile', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('parent-a').firestore(), 'users', 'teacher-a')));
});

test('teacher cannot access another institute profile', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-b')));
});

test('Firestore role field alone does not grant Super Admin access', async () => {
  const db = environment.authenticatedContext('fake-super').firestore();
  await assertFails(getDoc(doc(db, 'users', 'teacher-a')));
  await assertFails(createInstitute(db));
});

test('verified Super Admin claim can read profiles and create an institute', async () => {
  const db = superDb();
  const snapshot = await assertSucceeds(getDoc(doc(db, 'users', 'teacher-b')));
  assert.equal(snapshot.data().role, 'teacher');
  await assertSucceeds(createInstitute(db));
});

test('inactive Super Admin profile is rejected even with a custom claim', async () => {
  const db = environment.authenticatedContext('inactive-super', {
    superAdmin: true,
  }).firestore();
  await assertFails(getDoc(doc(db, 'institutes', 'institute-a')));
});

test('Institute Admin can read only its own institute and cannot create or edit', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'institutes', 'institute-a')));
  await assertFails(getDoc(doc(db, 'institutes', 'institute-b')));
  await assertFails(createInstitute(db));
  await assertFails(updateDoc(doc(db, 'institutes', 'institute-a'), { status: 'suspended', active: false }));
});

test('teacher and parent cannot view institute-management data', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'institutes', 'institute-a')));
  await assertFails(getDoc(doc(environment.authenticatedContext('parent-a').firestore(), 'institutes', 'institute-a')));
});

test('verified Super Admin can suspend and reactivate without changing usage', async () => {
  const reference = doc(superDb(), 'institutes', 'institute-a');
  await assertSucceeds(updateDoc(reference, {
    status: 'suspended', active: false, updatedAt: serverTimestamp(), updatedBy: 'real-super',
  }));
  await assertSucceeds(updateDoc(reference, {
    status: 'active', active: true, updatedAt: serverTimestamp(), updatedBy: 'real-super',
  }));
});

test('ordinary clients and Super Admin clients cannot alter SMS usage counters', async () => {
  await assertFails(updateDoc(doc(environment.authenticatedContext('admin-a').firestore(), 'sms_usage', 'institute-a'), { used: 8 }));
  await assertFails(updateDoc(doc(superDb(), 'sms_usage', 'institute-a'), { used: 8 }));
  await assertFails(updateDoc(doc(superDb(), 'institutes', 'institute-a'), {
    smsUsedThisMonth: 8, updatedAt: serverTimestamp(), updatedBy: 'real-super',
  }));
});

test('ordinary clients cannot create or delete audit logs', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertFails(setDoc(doc(db, 'audit_logs', 'log-a'), {
    auditLogId: 'log-a', actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'instituteUpdated', targetType: 'institute',
    targetId: 'institute-a', summary: 'Attempted write', createdAt: serverTimestamp(),
  }));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'audit_logs', 'seed-log'), { createdAt: new Date() });
  });
  await assertFails(deleteDoc(doc(db, 'audit_logs', 'seed-log')));
});

test('verified Super Admin can append but cannot edit or delete an audit log', async () => {
  const db = superDb();
  const reference = doc(db, 'audit_logs', 'log-super');
  await assertSucceeds(setDoc(reference, {
    auditLogId: 'log-super', actorUid: 'real-super', actorRole: 'superAdmin',
    instituteId: 'institute-a', action: 'instituteUpdated', targetType: 'institute',
    targetId: 'institute-a', summary: 'Institute details updated', createdAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(reference, { summary: 'Changed' }));
  await assertFails(deleteDoc(reference));
});

test('Super Admin can audit an Institute Admin password-reset request', async () => {
  const db = superDb();
  await assertSucceeds(setDoc(doc(db, 'audit_logs', 'reset-admin'), {
    auditLogId: 'reset-admin', actorUid: 'real-super', actorRole: 'superAdmin',
    instituteId: 'institute-a', action: 'passwordResetRequested', targetType: 'user',
    targetId: 'admin-a', summary: 'Password reset email requested for authorized account',
    createdAt: serverTimestamp(),
  }));
});

test('Institute Admin can audit only same-institute Teacher reset requests', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const audit = (id, targetId, extra = {}) => setDoc(doc(db, 'audit_logs', id), {
    auditLogId: id, actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'teacherPasswordResetRequested', targetType: 'teacher',
    targetId, summary: 'Password reset email requested for authorized account',
    createdAt: serverTimestamp(), ...extra,
  });
  await assertSucceeds(audit('reset-teacher-a', 'teacher-a'));
  await assertFails(audit('reset-teacher-b', 'teacher-b'));
  await assertFails(audit('reset-admin-a', 'admin-a'));
  await assertFails(audit('reset-sensitive', 'teacher-a', { resetLink: 'secret' }));
});

test('institute code format and uniqueness are enforced atomically', async () => {
  await assertFails(createInstitute(superDb(), 'bad-institute', 'lowercase'));
  await assertFails(createInstitute(superDb(), 'duplicate-institute', 'INSTA'));
});

test('privileged user profiles cannot be created directly by a client', async () => {
  await assertFails(setDoc(doc(superDb(), 'users', 'new-admin'), profile({
    uid: 'new-admin', role: 'instituteAdmin', instituteId: 'institute-a',
  })));
});

test('verified Super Admin can query teachers across institutes', async () => {
  const db = superDb();
  const snapshot = await assertSucceeds(getDocs(query(
    collection(db, 'users'), where('role', '==', 'teacher'),
  )));
  assert.ok(snapshot.docs.some((value) => value.id === 'teacher-a'));
  assert.ok(snapshot.docs.some((value) => value.id === 'teacher-b'));
});

test('active Institute Admin can query only own-institute teachers', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const snapshot = await assertSucceeds(getDocs(query(
    collection(db, 'users'),
    where('role', '==', 'teacher'),
    where('instituteId', '==', 'institute-a'),
  )));
  assert.ok(snapshot.docs.every((value) => value.data().instituteId === 'institute-a'));
  await assertFails(getDoc(doc(db, 'users', 'teacher-b')));
});

test('teacher cannot read another teacher or change protected fields', async () => {
  const db = environment.authenticatedContext('teacher-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'users', 'teacher-a')));
  await assertFails(getDoc(doc(db, 'users', 'teacher-b')));
  await assertFails(updateDoc(doc(db, 'users', 'teacher-a'), {
    permissions: { ...teacherPermissions, canCreateClasses: true },
  }));
  await assertFails(updateDoc(doc(db, 'users', 'teacher-a'), { role: 'instituteAdmin' }));
  await assertFails(updateDoc(doc(db, 'users', 'teacher-a'), { instituteId: 'institute-b' }));
});

test('parent cannot access teacher-management reservations or profiles', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  await assertFails(getDoc(doc(db, 'users', 'teacher-a')));
  await assertFails(getDoc(doc(db, 'teacher_employee_numbers', 'institute-a_EMP-A')));
});

test('direct teacher-profile creation is denied even to verified Super Admin', async () => {
  await assertFails(setDoc(doc(superDb(), 'users', 'new-teacher'), profile({
    uid: 'new-teacher', role: 'teacher', instituteId: 'institute-a',
    mustChangePassword: true,
  })));
});

test('authorized teacher updates require protected employee reservations', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertFails(setDoc(doc(db, 'teacher_employee_numbers', 'institute-a_HIJACK'), {
    instituteId: 'institute-a', employeeNumber: 'HIJACK', teacherUid: 'teacher-b',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  }));
  const batch = writeBatch(db);
  batch.set(doc(db, 'teacher_employee_numbers', 'institute-a_EMP-NEW'), {
    instituteId: 'institute-a', employeeNumber: 'EMP-NEW', teacherUid: 'teacher-a',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  });
  batch.update(doc(db, 'users', 'teacher-a'), {
    employeeNumber: 'EMP-NEW', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  });
  batch.delete(doc(db, 'teacher_employee_numbers', 'institute-a_EMP-A'));
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db, 'teacher_employee_numbers', 'institute-a_EMP-NEW'), {
    instituteId: 'institute-a', employeeNumber: 'EMP-NEW', teacherUid: 'teacher-a',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  }));
});

test('Institute Admin can append same-institute teacher audit but cannot edit or delete it', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const reference = doc(db, 'audit_logs', 'teacher-update');
  await assertSucceeds(setDoc(reference, {
    auditLogId: 'teacher-update', actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'teacherUpdated', targetType: 'teacher',
    targetId: 'teacher-a', summary: 'Teacher profile updated', createdAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(reference));
  await assertFails(updateDoc(reference, { summary: 'Tampered' }));
  await assertFails(deleteDoc(reference));
});

test('inactive Institute Admin and suspended institute cannot manage teachers', async () => {
  const inactiveDb = environment.authenticatedContext('inactive-admin').firestore();
  await assertFails(getDoc(doc(inactiveDb, 'users', 'teacher-a')));
  const suspendedDb = environment.authenticatedContext('admin-suspended').firestore();
  await assertFails(getDocs(query(
    collection(suspendedDb, 'users'), where('role', '==', 'teacher'),
    where('instituteId', '==', 'institute-suspended'),
  )));
});

test('verified Super Admin can disable and reactivate a teacher', async () => {
  const reference = doc(superDb(), 'users', 'teacher-a');
  await assertSucceeds(updateDoc(reference, {
    active: false, status: 'disabled', updatedAt: serverTimestamp(), updatedBy: 'real-super',
  }));
  await assertSucceeds(updateDoc(reference, {
    active: true, status: 'active', updatedAt: serverTimestamp(), updatedBy: 'real-super',
  }));
});

test('Institute Admin can create a class only with a same-institute code reservation', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'class_codes', 'institute-a_SCI-A'), {
    instituteId: 'institute-a', classCode: 'SCI-A', classId: 'class-new',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  });
  batch.set(doc(db, 'classes', 'class-new'), {
    ...academicClass({ id: 'class-new', code: 'SCI-A' }),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'audit_logs', 'class-new-audit'), {
    auditLogId: 'class-new-audit', actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'classCreated', targetType: 'academicClass',
    targetId: 'class-new', summary: 'Class created', createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db, 'classes', 'class-no-reservation'), {
    ...academicClass({ id: 'class-no-reservation', code: 'NO-RES' }),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
});

test('Institute Admin transaction creates class, reservation, and audit without reading a missing reservation', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertSucceeds(runTransaction(db, async transaction => {
    transaction.set(doc(db, 'classes', 'class-transaction'), {
      ...academicClass({ id: 'class-transaction', code: 'TXN-CLASS', teacherIds: [] }),
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    transaction.set(doc(db, 'class_codes', 'institute-a_TXN-CLASS'), {
      instituteId: 'institute-a', classCode: 'TXN-CLASS', classId: 'class-transaction',
      createdAt: serverTimestamp(), createdBy: 'admin-a',
    });
    transaction.set(doc(db, 'audit_logs', 'class-transaction-audit'), {
      auditLogId: 'class-transaction-audit', actorUid: 'admin-a', actorRole: 'instituteAdmin',
      instituteId: 'institute-a', action: 'classCreated', targetType: 'academicClass',
      targetId: 'class-transaction', summary: 'Class created', createdAt: serverTimestamp(),
    });
  }));
});

test('teacher class creation requires canCreateClasses and one assigned self', async () => {
  const deniedDb = environment.authenticatedContext('teacher-a').firestore();
  const denied = writeBatch(deniedDb);
  denied.set(doc(deniedDb, 'class_codes', 'institute-a_TEACH-1'), {
    instituteId: 'institute-a', classCode: 'TEACH-1', classId: 'teacher-class-1',
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
  });
  denied.set(doc(deniedDb, 'classes', 'teacher-class-1'), {
    ...academicClass({ id: 'teacher-class-1', code: 'TEACH-1', teacherIds: ['teacher-a'] }),
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
    updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  });
  await assertFails(denied.commit());

  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'users', 'teacher-a'), {
      permissions: { ...teacherPermissions, canCreateClasses: true },
    });
  });
  const db = environment.authenticatedContext('teacher-a').firestore();
  const allowed = writeBatch(db);
  allowed.set(doc(db, 'class_codes', 'institute-a_TEACH-2'), {
    instituteId: 'institute-a', classCode: 'TEACH-2', classId: 'teacher-class-2',
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
  });
  allowed.set(doc(db, 'classes', 'teacher-class-2'), {
    ...academicClass({ id: 'teacher-class-2', code: 'TEACH-2', teacherIds: ['teacher-a'] }),
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
    updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  });
  allowed.set(doc(db, 'audit_logs', 'teacher-class-2-audit'), {
    auditLogId: 'teacher-class-2-audit', actorUid: 'teacher-a', actorRole: 'teacher',
    instituteId: 'institute-a', action: 'classCreated', targetType: 'academicClass',
    targetId: 'teacher-class-2', summary: 'Class created', createdAt: serverTimestamp(),
  });
  await assertSucceeds(allowed.commit());

  const unrelated = writeBatch(db);
  unrelated.set(doc(db, 'class_codes', 'institute-a_TEACH-3'), {
    instituteId: 'institute-a', classCode: 'TEACH-3', classId: 'teacher-class-3',
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
  });
  unrelated.set(doc(db, 'classes', 'teacher-class-3'), {
    ...academicClass({ id: 'teacher-class-3', code: 'TEACH-3', teacherIds: [] }),
    createdAt: serverTimestamp(), createdBy: 'teacher-a',
    updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  });
  await assertFails(unrelated.commit());
});

test('teacher can edit only an assigned non-archived class without changing assignment or status', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'users', 'teacher-a'), {
      permissions: { ...teacherPermissions, canEditClasses: true },
    });
  });
  const db = environment.authenticatedContext('teacher-a').firestore();
  await assertSucceeds(updateDoc(doc(db, 'classes', 'class-a'), {
    name: 'Updated Mathematics', updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  }));
  await assertFails(updateDoc(doc(db, 'classes', 'class-a'), {
    teacherIds: [], primaryTeacherId: null, updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  }));
  await assertFails(updateDoc(doc(db, 'classes', 'class-a'), {
    status: 'inactive', active: false, updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  }));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'classes', 'class-a'), {
      status: 'archived', active: false,
    });
  });
  await assertFails(updateDoc(doc(db, 'classes', 'class-a'), {
    name: 'Archived edit', updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
  }));
});

test('Institute Admin manages own class and student lifecycle but cannot grant roles', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertSucceeds(updateDoc(doc(db, 'classes', 'class-a'), {
    status: 'inactive', active: false, updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
  await assertSucceeds(updateDoc(doc(db, 'classes', 'class-a'), {
    status: 'archived', active: false, updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
  await assertSucceeds(updateDoc(doc(db, 'students', 'student-a'), {
    status: 'suspended', active: false, updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
  await assertFails(updateDoc(doc(db, 'users', 'admin-a'), {
    role: 'superAdmin', instituteId: null, updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
  await assertFails(updateDoc(doc(db, 'classes', 'class-b'), {
    name: 'Cross institute edit', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
});

test('permission changes use one profile update and one safe audit entry', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const batch = writeBatch(db);
  batch.update(doc(db, 'users', 'teacher-a'), {
    permissions: {
      ...teacherPermissions,
      canCreateClasses: true,
      canCorrectAttendance: true,
    },
    updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  });
  batch.set(doc(db, 'audit_logs', 'bulk-permissions'), {
    auditLogId: 'bulk-permissions', actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'teacherPermissionsChanged', targetType: 'teacher',
    targetId: 'teacher-a',
    summary: 'Teacher permissions changed: canCorrectAttendance, canCreateClasses',
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const snapshot = await getDoc(doc(db, 'users', 'teacher-a'));
  assert.equal(snapshot.data().permissions.canCreateClasses, true);
  assert.equal(snapshot.data().permissions.canCorrectAttendance, true);
});

test('class code uniqueness and institute assignment are protected', async () => {
  const adminA = environment.authenticatedContext('admin-a').firestore();
  await assertFails(setDoc(doc(adminA, 'class_codes', 'institute-a_MATH-A'), {
    instituteId: 'institute-a', classCode: 'MATH-A', classId: 'duplicate',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  }));
  await assertFails(getDoc(doc(adminA, 'classes', 'class-b')));
});

test('direct class writes cannot inject a cross-institute secondary teacher', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertFails(updateDoc(doc(db, 'classes', 'class-a'), {
    teacherIds: ['teacher-a', 'teacher-b'], updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
});

test('assigned teacher reads own class and enrolment but not other institute data', async () => {
  const db = environment.authenticatedContext('teacher-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'classes', 'class-a')));
  await assertSucceeds(getDoc(doc(db, 'class_students', 'class-a_student-a')));
  await assertFails(getDoc(doc(db, 'classes', 'class-b')));
  await assertFails(getDoc(doc(db, 'students', 'student-b')));
  await assertFails(getDoc(doc(db, 'students', 'student-a')));
});

test('teacher cannot edit class assignment or student protected data directly', async () => {
  const db = environment.authenticatedContext('teacher-a').firestore();
  await assertFails(updateDoc(doc(db, 'classes', 'class-a'), { teacherIds: ['teacher-a', 'teacher-b'] }));
  await assertFails(updateDoc(doc(db, 'students', 'student-a'), { instituteId: 'institute-b' }));
  await assertFails(updateDoc(doc(db, 'students', 'student-a'), { qrTokenHash: 'b'.repeat(64) }));
  await assertFails(deleteDoc(doc(db, 'students', 'student-a')));
});

test('Institute Admin creates student only with unique reservation and cannot cross institutes', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'student_numbers', 'institute-a_STU-NEW'), {
    instituteId: 'institute-a', studentNumber: 'STU-NEW', studentId: 'student-new',
    createdAt: serverTimestamp(), createdBy: 'admin-a',
  });
  batch.set(doc(db, 'students', 'student-new'), {
    ...student({ id: 'student-new', number: 'STU-NEW' }),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(db, 'students', 'student-b')));
});

test('Institute Admin transaction creates student, number reservation, and audit without reading a missing reservation', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertSucceeds(runTransaction(db, async transaction => {
    transaction.set(doc(db, 'students', 'student-transaction'), {
      ...student({ id: 'student-transaction', number: 'STU-TXN' }),
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    transaction.set(doc(db, 'student_numbers', 'institute-a_STU-TXN'), {
      instituteId: 'institute-a', studentNumber: 'STU-TXN', studentId: 'student-transaction',
      createdAt: serverTimestamp(), createdBy: 'admin-a',
    });
    transaction.set(doc(db, 'audit_logs', 'student-transaction-audit'), {
      auditLogId: 'student-transaction-audit', actorUid: 'admin-a', actorRole: 'instituteAdmin',
      instituteId: 'institute-a', action: 'studentCreated', targetType: 'student',
      targetId: 'student-transaction', summary: 'Student created', createdAt: serverTimestamp(),
    });
  }));
});

test('parent and fake Super Admin cannot access academic management data', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('parent-a').firestore(), 'classes', 'class-a')));
  await assertFails(getDoc(doc(environment.authenticatedContext('fake-super').firestore(), 'classes', 'class-a')));
});

test('class/student deletion is denied and audit logs remain append-only', async () => {
  const db = environment.authenticatedContext('admin-a').firestore();
  await assertFails(deleteDoc(doc(db, 'classes', 'class-a')));
  await assertFails(deleteDoc(doc(db, 'students', 'student-a')));
  const audit = doc(db, 'audit_logs', 'academic-update');
  await assertSucceeds(setDoc(audit, {
    auditLogId: 'academic-update', actorUid: 'admin-a', actorRole: 'instituteAdmin',
    instituteId: 'institute-a', action: 'studentUpdated', targetType: 'student',
    targetId: 'student-a', summary: 'Student updated', createdAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(audit, { summary: 'Changed' }));
  await assertFails(deleteDoc(audit));
});

test('QR lookup and attendance writes are denied to every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'qr_tokens', 'opaque-hash'), { studentId: 'student-a', instituteId: 'institute-a', enabled: true, version: 1 });
    await setDoc(doc(db, 'attendance_sessions', 'session-a'), { sessionId: 'session-a', instituteId: 'institute-a', classId: 'class-a', status: 'open' });
    await setDoc(doc(db, 'attendance_records', 'session-a_student-a'), { attendanceRecordId: 'session-a_student-a', sessionId: 'session-a', instituteId: 'institute-a', classId: 'class-a', studentId: 'student-a' });
  });
  const contexts = [
    environment.unauthenticatedContext(), environment.authenticatedContext('parent-a'),
    environment.authenticatedContext('teacher-a'), environment.authenticatedContext('admin-a'),
    environment.authenticatedContext('real-super', { superAdmin: true }),
  ];
  for (const context of contexts) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, 'qr_tokens', 'opaque-hash')));
    await assertFails(getDoc(doc(db, 'attendance_sessions', 'session-a')));
    await assertFails(getDoc(doc(db, 'attendance_records', 'session-a_student-a')));
    await assertFails(setDoc(doc(db, 'attendance_records', 'forged'), { actorUid: 'someone-else' }));
  }
});

test('attendance and QR audits can be appended only by the trusted backend', async () => {
  const db = superDb();
  await assertFails(setDoc(doc(db, 'audit_logs', 'forged-attendance'), {
    auditLogId: 'forged-attendance', actorUid: 'real-super', actorRole: 'superAdmin',
    instituteId: 'institute-a', action: 'studentEntryRecorded', targetType: 'attendanceRecord',
    targetId: 'session-a_student-a', summary: 'Student entry recorded', createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, 'qr_tokens', 'new-hash'), {
    studentId: 'student-a', instituteId: 'institute-a', enabled: true, version: 2,
  }));
});

test('only an active parent can read their own active link', async () => {
  const parent = environment.authenticatedContext('parent-a').firestore();
  await assertSucceeds(getDoc(doc(parent, 'parent_student_links', 'parent-a_student-a')));
  await assertFails(getDoc(doc(parent, 'parent_student_links', 'parent-b_student-b')));
  await assertFails(getDoc(doc(parent, 'parent_student_links', 'parent-a_student-b')));
  await assertFails(getDoc(doc(environment.authenticatedContext('inactive-parent').firestore(), 'parent_student_links', 'parent-a_student-a')));
  await assertFails(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'parent_student_links', 'parent-a_student-a')));
});

test('parent clients cannot create update or delete parent links', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  const existing = doc(db, 'parent_student_links', 'parent-a_student-a');
  await assertFails(setDoc(doc(db, 'parent_student_links', 'parent-a_student-b'), {
    parentUid: 'parent-a', studentId: 'student-b', instituteId: 'institute-b', active: true,
  }));
  await assertFails(updateDoc(existing, { active: false }));
  await assertFails(deleteDoc(existing));
});

test('parent reads only linked safe student projection and never raw student data', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'parent_student_profiles', 'student-a')));
  await assertFails(getDoc(doc(db, 'parent_student_profiles', 'student-b')));
  await assertFails(getDoc(doc(db, 'students', 'student-a')));
  await assertFails(updateDoc(doc(db, 'parent_student_profiles', 'student-a'), { fullName: 'Changed' }));
});

test('parent reads only active linked class projections and cannot write them', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'parent_class_profiles', 'class-a')));
  await assertFails(getDoc(doc(db, 'parent_class_profiles', 'class-b')));
  await assertFails(updateDoc(doc(db, 'parent_class_profiles', 'class-a'), { room: 'Changed' }));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'parent_class_profiles', 'class-a'), { active: false });
  });
  await assertFails(getDoc(doc(db, 'parent_class_profiles', 'class-a')));
});

test('parent reads linked attendance summaries but all parent attendance writes fail', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  const own = doc(db, 'parent_attendance_summaries', 'student-a_2026-08-01_class-a');
  await assertSucceeds(getDoc(own));
  await assertFails(getDoc(doc(db, 'parent_attendance_summaries', 'student-b_2026-08-01_class-b')));
  await assertFails(setDoc(doc(db, 'parent_attendance_summaries', 'forged'), {
    studentId: 'student-a', instituteId: 'institute-a', classId: 'class-a', status: 'present',
  }));
  await assertFails(updateDoc(own, { status: 'absent' }));
  await assertFails(deleteDoc(own));
});

test('parent repository attendance query is bounded to the linked student', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  const attendance = query(
    collection(db, 'parent_attendance_summaries'),
    where('studentId', '==', 'student-a'),
    where('instituteId', '==', 'institute-a'),
    orderBy('attendanceDate', 'desc'),
    where('attendanceDate', '>=', new Date('2026-08-01T00:00:00Z')),
    where('attendanceDate', '<=', new Date('2026-08-01T23:59:59Z')),
    limit(100),
  );
  const result = await assertSucceeds(getDocs(attendance));
  assert.equal(result.size, 1);
  assert.equal(result.docs[0].data().studentId, 'student-a');
});

test('parent reads only active non-expired notices targeted to their scope', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  for (const id of ['notice-institute', 'notice-student', 'notice-class']) {
    await assertSucceeds(getDoc(doc(db, 'parent_notices', id)));
  }
  for (const id of [
    'notice-unrelated', 'notice-inactive', 'notice-expired',
    'notice-future-published',
  ]) {
    await assertFails(getDoc(doc(db, 'parent_notices', id)));
  }
  await assertFails(setDoc(doc(db, 'parent_notices', 'forged'), { active: true }));
  await assertFails(updateDoc(doc(db, 'parent_notices', 'notice-student'), { title: 'Changed' }));
  await assertFails(deleteDoc(doc(db, 'parent_notices', 'notice-student')));
});

test('parent reads only linked public institute identity and never private institute data', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'institute_public_profiles', 'institute-a')));
  await assertFails(getDoc(doc(db, 'institute_public_profiles', 'institute-b')));
  await assertFails(getDoc(doc(db, 'institutes', 'institute-a')));
  await assertFails(updateDoc(doc(db, 'institute_public_profiles', 'institute-a'), { displayName: 'Changed' }));
});

test('suspended institute blocks every parent-facing projection', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'institutes', 'institute-a'), { active: false, status: 'suspended' });
  });
  const db = environment.authenticatedContext('parent-a').firestore();
  for (const [collectionName, id] of [
    ['parent_student_links', 'parent-a_student-a'],
    ['parent_student_profiles', 'student-a'],
    ['parent_class_profiles', 'class-a'],
    ['parent_attendance_summaries', 'student-a_2026-08-01_class-a'],
    ['parent_notices', 'notice-institute'],
    ['institute_public_profiles', 'institute-a'],
  ]) await assertFails(getDoc(doc(db, collectionName, id)));
});

test('revoking the final link immediately removes every derived read scope', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await updateDoc(doc(db, 'parent_student_links', 'parent-a_student-a'), {
      active: false, revokedAt: new Date(), revokedBy: 'admin-a',
    });
    await updateDoc(doc(db, 'parent_access_scopes', 'parent-a'), {
      active: false, studentIds: [], classIds: [], instituteIds: [], updatedAt: new Date(),
    });
  });
  const db = environment.authenticatedContext('parent-a').firestore();
  for (const [collectionName, id] of [
    ['parent_student_profiles', 'student-a'],
    ['parent_class_profiles', 'class-a'],
    ['parent_attendance_summaries', 'student-a_2026-08-01_class-a'],
    ['parent_notices', 'notice-student'],
    ['parent_notices', 'notice-class'],
    ['institute_public_profiles', 'institute-a'],
  ]) await assertFails(getDoc(doc(db, collectionName, id)));
});

test('backend callable state is inaccessible to every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'backend_rate_limits', 'rate-a'), { actorHash: 'hash', count: 1 });
    await setDoc(doc(db, 'backend_idempotency', 'request-a'), { actorHash: 'hash', status: 'completed' });
    await setDoc(doc(db, 'backend_callable_audits', 'audit-a'), { actorHash: 'hash', outcome: 'allowed' });
  });
  const contexts = [
    environment.unauthenticatedContext(),
    environment.authenticatedContext('parent-a'),
    environment.authenticatedContext('teacher-a'),
    environment.authenticatedContext('admin-a'),
    environment.authenticatedContext('real-super', { superAdmin: true }),
  ];
  for (const context of contexts) {
    const db = context.firestore();
    for (const [collectionName, id] of [
      ['backend_rate_limits', 'rate-a'],
      ['backend_idempotency', 'request-a'],
      ['backend_callable_audits', 'audit-a'],
    ]) {
      await assertFails(getDoc(doc(db, collectionName, id)));
      await assertFails(setDoc(doc(db, collectionName, `forged-${id}`), { actorHash: 'forged' }));
    }
  }
});

test('notification device records are callable-only for every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'notification_devices', 'parent-a', 'tokens', 'device-a'), {
      uid: 'parent-a', tokenId: 'device-a', protectedToken: 'never-readable', active: true,
    });
  });
  const contexts = [
    environment.unauthenticatedContext(), environment.authenticatedContext('parent-a'),
    environment.authenticatedContext('teacher-a'), environment.authenticatedContext('admin-a'),
    environment.authenticatedContext('real-super', { superAdmin: true }),
  ];
  for (const context of contexts) {
    const db = context.firestore(); const own = doc(db, 'notification_devices', 'parent-a', 'tokens', 'device-a');
    await assertFails(getDoc(own));
    await assertFails(setDoc(own, { uid: 'parent-a', protectedToken: 'forged' }));
    await assertFails(updateDoc(own, { active: false }));
    await assertFails(deleteDoc(own));
  }
});

test('notification preferences remain callable-only for every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'notification_preferences', 'parent-a'), {
      uid: 'parent-a', notices: true, securityAlerts: true,
    });
  });
  const contexts = [
    environment.unauthenticatedContext(), environment.authenticatedContext('parent-a'),
    environment.authenticatedContext('teacher-a'), environment.authenticatedContext('admin-a'),
    environment.authenticatedContext('real-super', { superAdmin: true }),
  ];
  for (const context of contexts) {
    const db = context.firestore(); const own = doc(db, 'notification_preferences', 'parent-a');
    await assertFails(getDoc(own));
    await assertFails(setDoc(own, { uid: 'parent-a', notices: false }));
    await assertFails(updateDoc(own, { notices: false }));
    await assertFails(deleteDoc(own));
  }
});

test('institute join codes, requests, and memberships are callable-only for every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'institute_join_codes', 'DEMO-2026'), { instituteId: 'institute-a', active: true });
    await setDoc(doc(db, 'institute_memberships', 'teacher-a_institute-a'), { uid: 'teacher-a', instituteId: 'institute-a', role: 'teacher', status: 'active' });
    await setDoc(doc(db, 'institute_join_requests', 'request-a'), { uid: 'teacher-a', instituteId: 'institute-a', requestedRole: 'teacher', status: 'pending' });
  });
  const contexts = [
    environment.unauthenticatedContext(), environment.authenticatedContext('parent-a'),
    environment.authenticatedContext('teacher-a'), environment.authenticatedContext('admin-a'),
    environment.authenticatedContext('real-super', { superAdmin: true }),
  ];
  for (const context of contexts) {
    const db = context.firestore();
    for (const [collectionName, id] of [
      ['institute_join_codes', 'DEMO-2026'], ['institute_memberships', 'teacher-a_institute-a'],
      ['institute_join_requests', 'request-a'],
    ]) {
      const ref = doc(db, collectionName, id);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { forged: true }));
      await assertFails(deleteDoc(ref));
    }
  }
});

test('SMS trusted queues are denied to every mobile role', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'sms_outbox', 'message-a'), { protectedPhone: 'backend-only' });
  });
  for (const context of [environment.unauthenticatedContext(), environment.authenticatedContext('parent-a'), environment.authenticatedContext('teacher-a'), environment.authenticatedContext('admin-a'), environment.authenticatedContext('real-super', { superAdmin: true })]) {
    const db = context.firestore(); const ref = doc(db, 'sms_outbox', 'message-a');
    await assertFails(getDoc(ref)); await assertFails(setDoc(ref, { protectedPhone: 'forged' })); await assertFails(deleteDoc(ref));
  }
});

test('a linked active parent can record only minimal SMS consent for their child', async () => {
  const db = environment.authenticatedContext('parent-a').firestore();
  const consent = doc(db, 'student_sms_consents', 'student-a');
  await assertSucceeds(setDoc(consent, {
    studentId: 'student-a', instituteId: 'institute-a', granted: true, updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, 'student_sms_consents', 'student-b'), {
    studentId: 'student-b', instituteId: 'institute-b', granted: true, updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(consent, { protectedPhone: '+94770000000' }));
});

test('SMS consent does not broaden unrelated parent or inactive-parent access', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'student_sms_consents', 'student-a'), {
      studentId: 'student-a', instituteId: 'institute-a', granted: true, updatedAt: new Date(),
    });
  });
  await assertFails(getDoc(doc(environment.authenticatedContext('parent-b').firestore(), 'student_sms_consents', 'student-a')));
  await assertFails(getDoc(doc(environment.authenticatedContext('inactive-parent').firestore(), 'student_sms_consents', 'student-a')));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('admin-a').firestore(), 'student_sms_consents', 'student-a')));
  await assertFails(getDoc(doc(environment.authenticatedContext('admin-b').firestore(), 'student_sms_consents', 'student-a')));
});
