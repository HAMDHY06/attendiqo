import { describe, expect, it } from 'vitest';
import {
  finishSession,
  recordScan,
  regenerateQr,
  startSession,
} from '../src/attendance';
import { AppError, type AuthenticatedUser, type FirestoreDocument } from '../src/security';
import type { WorkerFirestoreAdmin } from '../src/worker-firestore-admin';

type Json = Record<string, unknown>;

function materialize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(materialize);
  if (value && typeof value === 'object') {
    const item = value as Json;
    if (typeof item.__attendiqoFirestoreTimestamp === 'string') {
      return item.__attendiqoFirestoreTimestamp;
    }
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

  async queryAssignments(field: 'classId' | 'studentId', value: string) {
    return [...this.docs.entries()]
      .filter(([path, document]) => path.startsWith('class_students/') && document.fields[field] === value)
      .map(([, document]) => document);
  }

  async queryAttendanceRecords(sessionId: string) {
    return [...this.docs.entries()]
      .filter(([path, document]) => path.startsWith('attendance_records/') && document.fields.sessionId === sessionId)
      .map(([, document]) => document);
  }

  async commit(
    writes: Array<{ path: string; fields: Json; updateTime?: string; createOnly?: boolean }>,
  ) {
    for (const write of writes) {
      if (write.createOnly && this.docs.has(write.path)) throw new AppError(409, 'conflict', 'conflict');
      const current = this.docs.get(write.path);
      if (write.updateTime && current?.updateTime !== write.updateTime) throw new AppError(409, 'conflict', 'conflict');
      this.docs.set(write.path, {
        fields: materialize(write.fields) as Json,
        updateTime: `v-${crypto.randomUUID()}`,
      });
    }
  }
}

const admin: AuthenticatedUser = {
  uid: 'admin-a',
  role: 'instituteAdmin',
  active: true,
  instituteId: 'institute-a',
  superAdmin: false,
};

function fixture() {
  const oldHash = 'a'.repeat(64);
  return new FakeFirestore(new Map([
    ['students/student-a', { updateTime: 'student-v1', fields: {
      studentId: 'student-a', instituteId: 'institute-a', fullName: 'Student A',
      status: 'active', active: true, qrEnabled: true, qrVersion: 1, qrTokenHash: oldHash,
    } }],
    [`qr_tokens/${oldHash}`, { updateTime: 'qr-v1', fields: {
      studentId: 'student-a', instituteId: 'institute-a', tokenHash: oldHash,
      version: 1, enabled: true, createdAt: '2026-09-01T00:00:00.000Z',
    } }],
    ['classes/class-a', { updateTime: 'class-v1', fields: {
      classId: 'class-a', instituteId: 'institute-a', active: true, status: 'active',
      teacherIds: ['teacher-a'], startTime: '08:00', endTime: '10:00',
    } }],
    ['class_students/class-a_student-a', { updateTime: 'assignment-v1', fields: {
      assignmentId: 'class-a_student-a', instituteId: 'institute-a', classId: 'class-a',
      studentId: 'student-a', active: true, status: 'active',
    } }],
  ]));
}

describe('trusted attendance boundary', () => {
  it('regenerates a one-time QR, persists only its hash, and revokes the old credential', async () => {
    const firestore = fixture();
    const result = await regenerateQr({ firestore, user: admin, payload: { studentId: 'student-a' } });
    const payload = result.payload as string;
    const credential = result.credential as Json;
    expect(payload).toMatch(/^attendiqo:\/\/student\/[A-Za-z0-9_-]{40,128}$/);
    expect(credential.tokenHash).toMatch(/^[a-f0-9]{64}$/);
    expect(JSON.stringify([...firestore.docs.values()])).not.toContain(payload);
    expect(firestore.docs.get(`qr_tokens/${'a'.repeat(64)}`)?.fields.enabled).toBe(false);
    expect(firestore.docs.get('students/student-a')?.fields.qrTokenHash).toBe(credential.tokenHash);
  });

  it('starts an institute-scoped session, accepts one scan, and rejects a duplicate', async () => {
    const firestore = fixture();
    const generated = await regenerateQr({ firestore, user: admin, payload: { studentId: 'student-a' } });
    const tokenHash = (generated.credential as Json).tokenHash as string;
    const started = await startSession({ firestore, user: admin, payload: { classId: 'class-a', date: '2026-09-03' } });
    const sessionId = (started.session as Json).sessionId as string;
    const request = { firestore, user: admin, payload: { sessionId, tokenHash, mode: 'entry', deviceId: 'device-a' } };
    const accepted = await recordScan(request);
    expect(accepted).toMatchObject({ status: 'accepted', studentId: 'student-a' });
    expect((accepted.record as Json).entryTime).toMatch(/^\d{4}-/);
    await expect(recordScan(request)).rejects.toMatchObject({
      code: 'duplicate_entry',
    } satisfies Partial<AppError>);
  });

  it('creates confirmed absent records before atomically closing a session', async () => {
    const firestore = fixture();
    firestore.docs.set('students/student-b', { updateTime: 'student-b-v1', fields: {
      studentId: 'student-b', instituteId: 'institute-a', status: 'active', active: true,
      qrEnabled: true, qrVersion: 1, qrTokenHash: 'e'.repeat(64),
    } });
    firestore.docs.set('class_students/class-a_student-b', { updateTime: 'assignment-b-v1', fields: {
      assignmentId: 'class-a_student-b', instituteId: 'institute-a', classId: 'class-a',
      studentId: 'student-b', active: true, status: 'active',
    } });
    const started = await startSession({ firestore, user: admin, payload: { classId: 'class-a', date: '2026-09-03' } });
    const sessionId = (started.session as Json).sessionId as string;
    const closed = await finishSession({ firestore, user: admin, payload: { sessionId } }, false);
    expect(closed.session).toMatchObject({ status: 'closed', absentCount: 2, totalStudents: 2 });
    expect(firestore.docs.get(`attendance_records/${sessionId}_student-a`)?.fields.status).toBe('absent');
    expect(firestore.docs.get(`attendance_records/${sessionId}_student-b`)?.fields.status).toBe('absent');
  });
});
