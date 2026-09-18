import { describe, expect, it } from 'vitest';
import {
  bootstrapParent,
  createInstituteAdminAccount,
  createTeacherAccount,
  linkParentStudent,
} from '../src/accounts';
import type { WorkerFirestoreAdmin } from '../src/worker-firestore-admin';
import type { WorkerIdentityAdmin } from '../src/worker-identity-admin';

function fixtures() {
  const documents = new Map<string, { fields: Record<string, unknown>; updateTime?: string }>([
    ['institutes/institute-a', { fields: { instituteId: 'institute-a', active: true, status: 'active' }, updateTime: 'v1' }],
    ['users/parent-a', { fields: { uid: 'parent-a', email: 'parent@test.example', displayName: 'Parent', role: 'parent', phoneNumber: '+94770000001', active: true }, updateTime: 'v1' }],
    ['students/student-a', { fields: { studentId: 'student-a', instituteId: 'institute-a', studentNumber: 'STU-1', fullName: 'Student A', primaryParentMobile: '+94770000001', active: true, status: 'active' }, updateTime: 'v1' }],
    ['classes/class-a', { fields: { classId: 'class-a', instituteId: 'institute-a', name: 'Class A', subject: 'Maths', grade: '8', primaryTeacherId: null, daysOfWeek: ['monday'], startTime: '08:00', endTime: '09:00', roomOrLocation: 'A', active: true, status: 'active' }, updateTime: 'v1' }],
  ]);
  const commits: Array<Array<{ path: string; fields: Record<string, unknown> }>> = [];
  const firestore: WorkerFirestoreAdmin = {
    get: async (path) => documents.get(path),
    queryMemberships: async () => [], queryJoinRequests: async () => [], queryPendingInstituteAdminRequests: async () => [],
    queryAssignments: async (field, value) => field === 'studentId' && value === 'student-a' ? [{ fields: { studentId: 'student-a', classId: 'class-a', instituteId: 'institute-a', active: true, status: 'active' } }] : [],
    queryAttendanceRecords: async () => [],
    queryStudentsByInstitute: async () => [documents.get('students/student-a')!],
    queryParentLinks: async () => [],
    commit: async (writes) => { commits.push(writes); for (const write of writes) documents.set(write.path, { fields: write.fields, updateTime: 'next' }); },
  };
  const identityEvents: string[] = [];
  const identity: WorkerIdentityAdmin = {
    createUser: async ({ uid }) => { identityEvents.push(`create:${uid}`); return uid; },
    setClaims: async (uid) => { identityEvents.push(`claims:${uid}`); },
    setDisabled: async (uid, disabled) => { identityEvents.push(`disabled:${uid}:${disabled}`); },
    deleteUser: async (uid) => { identityEvents.push(`delete:${uid}`); },
  };
  return { firestore, identity, documents, commits, identityEvents };
}

const permissions = Object.fromEntries([
  'canCreateClasses', 'canEditClasses', 'canAddStudents', 'canEditStudents', 'canGenerateQrCodes',
  'canTakeAttendance', 'canCorrectAttendance', 'canExportReports', 'canViewParentContacts', 'canSendManualNotifications',
].map((name) => [name, true]));

describe('trusted account and parent workflows', () => {
  it('creates a teacher with Auth claims, active membership and one-time password', async () => {
    const state = fixtures();
    const result = await createTeacherAccount({
      firestore: state.firestore, identity: state.identity,
      user: { uid: 'admin-a', role: 'instituteAdmin', active: true, instituteId: 'institute-a', superAdmin: false },
      payload: { instituteId: 'institute-a', email: 'teacher@test.example', displayName: 'Teacher', phoneNumber: null, employeeNumber: 'EMP-1', permissions },
    });
    expect(result.role).toBe('teacher');
    expect((result.temporaryPassword as string).length).toBe(16);
    expect(state.identityEvents.some((event) => event.startsWith('claims:'))).toBe(true);
    expect(state.commits.flat().some((write) => write.path.startsWith('institute_memberships/'))).toBe(true);
    expect(JSON.stringify(state.commits)).not.toContain(result.temporaryPassword as string);
  });

  it('requires a verified Super Admin for Institute Admin creation', async () => {
    const state = fixtures();
    await expect(createInstituteAdminAccount({
      firestore: state.firestore, identity: state.identity,
      user: { uid: 'admin-a', role: 'instituteAdmin', active: true, instituteId: 'institute-a', superAdmin: false },
      payload: { instituteId: 'institute-a', email: 'admin2@test.example', displayName: 'Admin 2' },
    })).rejects.toMatchObject({ code: 'forbidden' });
  });

  it('bootstraps only the signed-in parent and normalizes the mobile number', async () => {
    const state = fixtures();
    await bootstrapParent(state.firestore, { uid: 'new-parent', email: 'new@test.example' }, { displayName: 'New Parent', mobileNumber: '0771234567' });
    const profile = state.documents.get('users/new-parent')?.fields;
    expect(profile?.role).toBe('parent');
    expect(profile?.phoneNumber).toBe('+94771234567');
    expect(profile?.parentLinkedStudentIds).toEqual([]);
  });

  it('links a child only after the registered mobile matches and builds safe projections', async () => {
    const state = fixtures();
    const result = await linkParentStudent(state.firestore, { uid: 'parent-a', role: 'parent', active: true, instituteId: 'institute-a', superAdmin: false }, { studentNumber: 'stu-1' });
    expect(result.status).toBe('linked');
    expect(state.documents.get('parent_student_links/parent-a_student-a')?.fields.active).toBe(true);
    expect(state.documents.get('parent_student_profiles/student-a')?.fields).not.toHaveProperty('primaryParentMobile');
    expect(state.documents.get('parent_access_scopes/parent-a')?.fields.studentIds).toEqual(['student-a']);
  });
});
