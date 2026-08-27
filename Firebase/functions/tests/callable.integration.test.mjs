import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { createCallableBoundary } from '../lib/callable_core.mjs';
import * as writers from '../lib/projection_writers.mjs';

let app;
let db;
let boundary;
const appCheck = { appId: 'attendiqo-admin-emulator' };

const institute = (id, active = true) => ({
  instituteId: id, name: `Institute ${id}`, active,
  status: active ? 'active' : 'suspended', sourceVersion: 1,
});
const user = (uid, role, instituteId = null, active = true) => ({
  uid, role, instituteId, active, displayName: uid, email: `${uid}@example.test`,
});
const student = (id, instituteId, active = true) => ({
  studentId: id, instituteId, active, fullName: `Student ${id}`,
  studentNumber: id.toUpperCase(), grade: '10', sourceVersion: 1,
  primaryParentMobile: '+94770000000', qrTokenHash: 'secret',
});
const academicClass = (id, instituteId) => ({
  classId: id, instituteId, name: `Class ${id}`, subject: 'Mathematics',
  grade: '10', roomOrLocation: 'Room 1', daysOfWeek: ['monday'],
  startTime: '08:00', endTime: '09:00', active: true, status: 'active',
  primaryTeacherId: null, sourceVersion: 1,
});

async function clearFirestore() {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
}

async function seed() {
  const writes = [
    db.collection('institutes').doc('institute-a').set(institute('institute-a')),
    db.collection('institutes').doc('institute-b').set(institute('institute-b')),
    db.collection('users').doc('admin-a').set(user('admin-a', 'instituteAdmin', 'institute-a')),
    db.collection('users').doc('admin-b').set(user('admin-b', 'instituteAdmin', 'institute-b')),
    db.collection('users').doc('inactive-admin').set(user('inactive-admin', 'instituteAdmin', 'institute-a', false)),
    db.collection('users').doc('teacher-a').set(user('teacher-a', 'teacher', 'institute-a')),
    db.collection('users').doc('parent-a').set(user('parent-a', 'parent')),
    db.collection('users').doc('inactive-parent').set(user('inactive-parent', 'parent', null, false)),
    db.collection('students').doc('student-a').set(student('student-a', 'institute-a')),
    db.collection('students').doc('inactive-student').set(student('inactive-student', 'institute-a', false)),
    db.collection('students').doc('student-b').set(student('student-b', 'institute-b')),
    db.collection('classes').doc('class-a').set(academicClass('class-a', 'institute-a')),
    db.collection('classes').doc('class-b').set(academicClass('class-b', 'institute-b')),
  ];
  await Promise.all(writes);
}

const request = (uid, data, { checked = true } = {}) => ({
  auth: uid ? { uid, token: { email_verified: true } } : null,
  app: checked ? appCheck : null,
  data,
});
const key = (suffix) => `phase7-emulator-${suffix}`;
const call = (operation, uid, data, options) => boundary({
  operation,
  request: request(uid, { idempotencyKey: key(`${operation}-${data.studentId ?? data.classId ?? data.instituteId ?? 'request'}`), ...data }, options),
});

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'FIRESTORE_EMULATOR_HOST is required.');
  app = initializeApp({ projectId: 'attendiqo-system' }, `callable-tests-${Date.now()}`);
  db = getFirestore(app);
  boundary = createCallableBoundary({ firestore: db, writers, maxRequests: 50 });
});
beforeEach(async () => { await clearFirestore(); await seed(); });
after(async () => { await clearFirestore(); await deleteApp(app); });

test('unauthenticated and invalid-token contexts are rejected safely', async () => {
  for (const invalidRequest of [
    request(null, { idempotencyKey: key('none'), studentId: 'student-a' }),
    { ...request(null, { idempotencyKey: key('invalid'), studentId: 'student-a' }), rawRequest: { headers: { authorization: 'Bearer invalid-token' } } },
  ]) await assert.rejects(
    boundary({ operation: 'syncStudentProjection', request: invalidRequest }),
    (error) => error.code === 'unauthenticated' && !error.message.includes('token'),
  );
});

test('missing App Check is rejected before administrative reads', async () => {
  await assert.rejects(
    call('syncStudentProjection', 'admin-a', { studentId: 'student-a' }, { checked: false }),
    (error) => error.code === 'failed-precondition' && error.message === 'App verification is required.',
  );
});

test('wrong role inactive admin and cross-institute actor are denied', async () => {
  for (const uid of ['teacher-a', 'inactive-admin', 'admin-b']) {
    await assert.rejects(
      call('syncStudentProjection', uid, { studentId: 'student-a' }),
      (error) => error.code === 'permission-denied',
    );
  }
});

test('inactive parent and inactive student are rejected', async () => {
  await assert.rejects(call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'inactive-parent', studentId: 'student-a', relationship: 'parent',
  }), (error) => error.code === 'permission-denied');
  await assert.rejects(call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'inactive-student', relationship: 'parent',
  }), (error) => error.code === 'permission-denied');
});

test('valid link creation is atomic and an identical retry is idempotent', async () => {
  const data = { parentUid: 'parent-a', studentId: 'student-a', relationship: 'guardian' };
  const first = await call('createOrReactivateParentLink', 'admin-a', data);
  const retry = await call('createOrReactivateParentLink', 'admin-a', data);
  assert.deepEqual(first, { ok: true, operation: 'createOrReactivateParentLink', replayed: false });
  assert.equal(retry.replayed, true);
  assert.equal((await db.collection('parent_student_links').doc('parent-a_student-a').get()).data().active, true);
  assert.deepEqual(
    (await db.collection('users').doc('parent-a').get()).data().parentLinkedStudentIds,
    ['student-a'],
  );
  assert.equal((await db.collection('parent_student_profiles').doc('student-a').get()).data().qrTokenHash, undefined);
  const domainAudits = await db.collection('audit_logs').where('action', '==', 'parentLinkCreated').get();
  assert.equal(domainAudits.size, 1);
  const beforeRetry = (await db.collection('parent_student_links')
    .doc('parent-a_student-a').get()).data().updatedAt.toMillis();
  await writers.upsertParentLink({
    firestore: db, actorUid: 'admin-a', parentUid: 'parent-a',
    studentId: 'student-a', relationship: 'guardian',
  });
  const afterRetry = (await db.collection('parent_student_links')
    .doc('parent-a_student-a').get()).data().updatedAt.toMillis();
  assert.equal(afterRetry, beforeRetry);
});

test('revocation and explicit reactivation preserve history safely', async () => {
  await call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'student-a', relationship: 'parent',
  });
  await call('revokeParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'student-a',
    idempotencyKey: key('revoke-parent-a'),
  });
  assert.equal((await db.collection('parent_student_links').doc('parent-a_student-a').get()).data().active, false);
  assert.deepEqual(
    (await db.collection('users').doc('parent-a').get()).data().parentLinkedStudentIds,
    [],
  );
  await assert.rejects(call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'student-a', relationship: 'parent',
    idempotencyKey: key('reactivate-missing'),
  }), (error) => error.code === 'failed-precondition');
  const result = await call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'student-a', relationship: 'parent', reactivate: true,
    idempotencyKey: key('reactivate-explicit'),
  });
  assert.equal(result.ok, true);
  assert.deepEqual(
    (await db.collection('users').doc('parent-a').get()).data().parentLinkedStudentIds,
    ['student-a'],
  );
});

test('all projection callable operations reach the canonical writers', async () => {
  await call('syncStudentProjection', 'admin-a', { studentId: 'student-a' });
  await call('syncClassProjection', 'admin-a', { classId: 'class-a' });
  await db.collection('attendance_records').doc('attendance-a').set({
    summaryId: 'student-a_2026-08-02_class-a', studentId: 'student-a',
    instituteId: 'institute-a', classId: 'class-a', attendanceDate: Timestamp.now(),
    attendanceDateKey: '2026-08-02',
    status: 'present', entryTime: Timestamp.now(), exitTime: null, late: false,
    currentPresenceState: 'inside', sourceVersion: 1,
  });
  await call('syncAttendanceSummary', 'admin-a', { sourceRecordId: 'attendance-a' });
  await call('syncParentNotice', 'admin-a', { notice: {
    noticeId: 'notice-a', instituteId: 'institute-a', title: 'Notice', message: 'Safe message',
    priority: 'normal', publishedAt: Timestamp.now(), expiresAt: null, active: true,
    targetType: 'student', targetStudentIds: ['student-a'], targetClassIds: [], sourceVersion: 1,
  } });
  await call('syncInstitutePublicProfile', 'admin-a', { instituteId: 'institute-a' });
  assert.equal((await db.collection('parent_class_profiles').doc('class-a').get()).exists, true);
  assert.equal((await db.collection('parent_attendance_summaries').doc('student-a_2026-08-02_class-a').get()).exists, true);
  assert.equal((await db.collection('parent_notices').doc('notice-a').get()).exists, true);
  assert.equal((await db.collection('institute_public_profiles').doc('institute-a').get()).exists, true);
});

test('link creation recomputes access scope and validates assigned classes', async () => {
  await db.collection('parent_access_scopes').doc('parent-a').set({
    parentUid: 'parent-a', active: true, studentIds: ['stale-student'],
    classIds: ['stale-class'], instituteIds: ['stale-institute'],
  });
  await db.collection('class_students').doc('assignment-a').set({
    assignmentId: 'assignment-a', studentId: 'student-a', classId: 'class-a',
    instituteId: 'institute-a', active: true, sourceVersion: 2,
  });
  await call('createOrReactivateParentLink', 'admin-a', {
    parentUid: 'parent-a', studentId: 'student-a', relationship: 'parent',
  });
  const scope = (await db.collection('parent_access_scopes').doc('parent-a').get()).data();
  assert.deepEqual(scope.studentIds, ['student-a']);
  assert.deepEqual(scope.classIds, ['class-a']);
  assert.deepEqual(scope.instituteIds, ['institute-a']);
  assert.deepEqual(
    (await db.collection('users').doc('parent-a').get()).data().parentLinkedStudentIds,
    ['student-a'],
  );

  await db.collection('class_students').doc('assignment-a').set({
    assignmentId: 'assignment-a', studentId: 'student-a', classId: 'class-a',
    instituteId: 'institute-a', active: false, sourceVersion: 3,
  });
  await call('syncStudentProjection', 'admin-a', {
    studentId: 'student-a', idempotencyKey: key('remove-class-assignment'),
  });
  const scopeAfterRemoval = (await db.collection('parent_access_scopes')
    .doc('parent-a').get()).data();
  assert.deepEqual(scopeAfterRemoval.studentIds, ['student-a']);
  assert.deepEqual(scopeAfterRemoval.classIds, []);

  await db.collection('class_students').doc('assignment-a').set({
    assignmentId: 'assignment-a', studentId: 'student-a', classId: 'class-b',
    instituteId: 'institute-a', active: true, sourceVersion: 4,
  });
  await assert.rejects(call('syncStudentProjection', 'admin-a', {
    studentId: 'student-a', idempotencyKey: key('cross-class-assignment'),
  }), (error) => error.code === 'permission-denied');
});

test('class projection derives the next non-expired authoritative schedule change', async () => {
  const tomorrow = new Date(Date.now() + 86400000);
  const yesterday = new Date(Date.now() - 2 * 86400000);
  await Promise.all([
    db.collection('class_schedule_changes').doc('expired-change').set({
      scheduleChangeId: 'expired-change', instituteId: 'institute-a', classId: 'class-a',
      effectiveDate: Timestamp.fromDate(yesterday), newStartTime: '07:00',
      newEndTime: '08:00', newRoomOrLocation: 'Old room', status: 'scheduled',
      sourceVersion: 2,
    }),
    db.collection('class_schedule_changes').doc('future-change').set({
      scheduleChangeId: 'future-change', instituteId: 'institute-a', classId: 'class-a',
      effectiveDate: Timestamp.fromDate(tomorrow), newStartTime: '10:00',
      newEndTime: '11:30', newRoomOrLocation: 'Room 2', status: 'scheduled',
      sourceVersion: 3,
    }),
  ]);
  await call('syncClassProjection', 'admin-a', { classId: 'class-a' });
  const projection = (await db.collection('parent_class_profiles').doc('class-a').get()).data();
  assert.equal(projection.effectiveSchedule.startTime, '10:00');
  assert.equal(projection.effectiveSchedule.endTime, '11:30');
  assert.equal(projection.effectiveSchedule.room, 'Room 2');
});

test('attendance synchronization enforces deterministic identity and applies corrections', async () => {
  const source = db.collection('attendance_records').doc('attendance-correction');
  await source.set({
    summaryId: 'student-a_2026-08-02_class-a', studentId: 'student-a',
    instituteId: 'institute-a', classId: 'class-a', attendanceDate: Timestamp.now(),
    attendanceDateKey: '2026-08-02', status: 'present', entryTime: Timestamp.now(),
    exitTime: null, late: false, currentPresenceState: 'inside', sourceVersion: 1,
  });
  await call('syncAttendanceSummary', 'admin-a', { sourceRecordId: source.id });
  await source.update({
    status: 'late', late: true, currentPresenceState: 'departed',
    exitTime: Timestamp.now(), sourceVersion: 2,
  });
  await call('syncAttendanceSummary', 'admin-a', {
    sourceRecordId: source.id, idempotencyKey: key('attendance-correction-2'),
  });
  const projection = (await db.collection('parent_attendance_summaries')
    .doc('student-a_2026-08-02_class-a').get()).data();
  assert.equal(projection.status, 'late');
  assert.equal(projection.currentPresenceState, 'departed');
  const audits = await db.collection('audit_logs')
    .where('action', '==', 'parentAttendanceProjectionUpdated').get();
  assert.equal(audits.size, 2);

  await source.update({ summaryId: 'forged-summary', sourceVersion: 3 });
  await assert.rejects(call('syncAttendanceSummary', 'admin-a', {
    sourceRecordId: source.id, idempotencyKey: key('attendance-forged-id'),
  }), (error) => error.code === 'invalid-argument');
});

test('trusted reconciliation can reflect a suspended institute publicly', async () => {
  await db.collection('institutes').doc('institute-a').update({
    active: false, status: 'suspended', sourceVersion: 2,
  });
  await writers.syncInstitutePublicProfile({
    firestore: db, actorUid: 'trusted-projection-sync',
    instituteId: 'institute-a', trustedSystem: true,
  });
  const projection = (await db.collection('institute_public_profiles')
    .doc('institute-a').get()).data();
  assert.equal(projection.status, 'suspended');
});

test('notice synchronization rejects cross-institute targets safely', async () => {
  await assert.rejects(call('syncParentNotice', 'admin-a', { notice: {
    noticeId: 'cross-notice', instituteId: 'institute-a', title: 'Notice', message: 'Safe message',
    priority: 'normal', active: true, targetType: 'class',
    targetStudentIds: [], targetClassIds: ['class-b'],
  } }), (error) => error.code === 'permission-denied');
});

test('student institute invalidation callable revokes old links', async () => {
  await db.collection('parent_student_links').doc('parent-a_student-b').set({
    parentUid: 'parent-a', studentId: 'student-b', instituteId: 'institute-a', active: true,
  });
  await db.collection('parent_student_profiles').doc('student-b').set({
    studentId: 'student-b', instituteId: 'institute-a', classIds: ['class-a'], sourceVersion: 1,
  });
  await db.collection('parent_access_scopes').doc('parent-a').set({
    parentUid: 'parent-a', active: true, studentIds: ['student-b'],
    classIds: ['class-a'], instituteIds: ['institute-a'],
  });
  await call('invalidateStudentInstituteLinks', 'admin-b', {
    studentId: 'student-b', previousInstituteId: 'institute-a', nextInstituteId: 'institute-b',
  });
  assert.equal((await db.collection('parent_student_links').doc('parent-a_student-b').get()).data().active, false);
});

test('rate limits and audits contain only safe metadata', async () => {
  const limited = createCallableBoundary({ firestore: db, writers, maxRequests: 1, now: () => 1000 });
  const makeRequest = (suffix) => ({
    operation: 'syncStudentProjection',
    request: request('admin-a', { idempotencyKey: key(suffix), studentId: 'student-a' }),
  });
  await limited(makeRequest('limit-one'));
  await assert.rejects(limited(makeRequest('limit-two')), (error) => error.code === 'resource-exhausted');
  const audits = await db.collection('backend_callable_audits').get();
  assert.ok(audits.size >= 2);
  for (const audit of audits.docs) {
    const serialized = JSON.stringify(audit.data());
    assert.equal(/email|mobile|password|token|student-a|parent-a/i.test(serialized), false);
  }
});
