import { describe, expect, it } from 'vitest';
import { createTeacherStudent, listTeacherStudents, updateTeacherStudent } from '../src/students';
import { AppError, type AuthenticatedUser, type FirestoreDocument } from '../src/security';
import type { WorkerFirestoreAdmin } from '../src/worker-firestore-admin';

type Json = Record<string, unknown>;
function materialize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(materialize);
  if (value && typeof value === 'object') {
    const item = value as Json;
    if (typeof item.__attendiqoFirestoreTimestamp === 'string') return item.__attendiqoFirestoreTimestamp;
    return Object.fromEntries(Object.entries(item).map(([key, child]) => [key, materialize(child)]));
  }
  return value;
}
class FakeFirestore implements WorkerFirestoreAdmin {
  constructor(readonly docs = new Map<string, FirestoreDocument>()) {}
  async get(path: string) { return this.docs.get(path); }
  async queryMemberships() { return []; }
  async queryJoinRequests() { return []; }
  async queryPendingInstituteAdminRequests() { return []; }
  async queryAttendanceRecords() { return []; }
  async queryStudentsByInstitute() { return []; }
  async queryParentLinks() { return []; }
  async queryParentLinksByStudent() { return []; }
  async queryNotificationTokens() { return []; }
  async queryClassesByTeacher(uid: string) { return [...this.docs.entries()].filter(([path, value]) => path.startsWith('classes/') && (value.fields.teacherIds as string[]).includes(uid)).map(([, value]) => value); }
  async queryAssignments(field: 'classId' | 'studentId', value: string) { return [...this.docs.entries()].filter(([path, document]) => path.startsWith('class_students/') && document.fields[field] === value).map(([, document]) => document); }
  async commit(writes: Array<{ path: string; fields: Json; updateTime?: string; createOnly?: boolean }>) {
    for (const write of writes) {
      if (write.createOnly && this.docs.has(write.path)) throw new AppError(409, 'conflict', 'conflict');
      this.docs.set(write.path, { fields: materialize(write.fields) as Json, updateTime: 'next' });
    }
  }
}
const teacher: AuthenticatedUser = { uid: 'teacher-a', role: 'teacher', active: true, instituteId: 'institute-a', superAdmin: false };
const permissions = { canAddStudents: true, canEditStudents: true, canViewParentContacts: true, canGenerateQrCodes: false };
function fixture() {
  return new FakeFirestore(new Map([
    ['users/teacher-a', { fields: { uid: 'teacher-a', instituteId: 'institute-a', active: true, permissions } }],
    ['classes/class-a', { fields: { classId: 'class-a', instituteId: 'institute-a', active: true, status: 'active', teacherIds: ['teacher-a'] } }],
  ]));
}
const studentPayload = { studentId: 'ignored', classId: 'class-a', studentNumber: 'STU-1', fullName: 'Student One', preferredName: null, address: '', primaryParentName: 'Parent One', primaryParentMobile: '0771234567', secondaryParentName: null, secondaryParentMobile: null, parentEmail: null, emergencyContactName: null, emergencyContactMobile: null, status: 'active', active: true };

describe('trusted teacher student boundary', () => {
  it('creates and assigns a student without returning a QR secret when QR permission is off', async () => {
    const firestore = fixture();
    const result = await createTeacherStudent({ firestore, user: teacher, payload: studentPayload });
    expect(result).not.toHaveProperty('qrPayload');
    const student = result.student as Json;
    expect(student.qrTokenHash).toBe('0'.repeat(64));
    expect([...firestore.docs.keys()].some((path) => path.startsWith('class_students/class-a_student-'))).toBe(true);
    expect(JSON.stringify(result)).not.toContain(firestore.docs.get(`students/${student.studentId}`)?.fields.qrTokenHash as string);
  });

  it('lists and updates only students assigned to the signed-in teacher', async () => {
    const firestore = fixture();
    const created = await createTeacherStudent({ firestore, user: teacher, payload: studentPayload });
    const student = created.student as Json;
    const listed = await listTeacherStudents({ firestore, user: teacher, payload: {} });
    expect((listed.students as Json[]).map((item) => item.studentId)).toEqual([student.studentId]);
    const updated = await updateTeacherStudent({ firestore, user: teacher, payload: { ...studentPayload, classId: undefined, studentId: student.studentId, fullName: 'Student Updated' } });
    expect((updated.student as Json).fullName).toBe('Student Updated');
  });
});
