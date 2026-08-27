import test from 'node:test';
import assert from 'node:assert/strict';
import {
  assertNewerVersion,
  attendanceProjection,
  classProjection,
  deterministicAttendanceSummaryId,
  deterministicParentLinkId,
  institutePublicProjection,
  noticeProjection,
  safeAuditPayload,
  studentProjection,
  validateExistingLink,
  validateLinkSources,
} from '../lib/parent_projection_validation.mjs';

test('link IDs are deterministic and validated', () => {
  assert.equal(deterministicParentLinkId('parent-a', 'student-a'), 'parent-a_student-a');
  assert.throws(() => deterministicParentLinkId('', 'student-a'));
});

test('attendance summary IDs use an explicit stable date key', () => {
  assert.equal(
    deterministicAttendanceSummaryId('student-a', '2026-08-02', 'class-a'),
    'student-a_2026-08-02_class-a',
  );
  assert.throws(() => deterministicAttendanceSummaryId('student-a', '08/02/2026', 'class-a'));
});

test('source versions reject rollback and permit idempotent retry', () => {
  assert.equal(assertNewerVersion(3, 3), 3);
  assert.equal(assertNewerVersion(3, 4), 4);
  assert.throws(() => assertNewerVersion(4, 3), /Stale/);
});

test('link source validation rejects inactive and cross-institute records', () => {
  const valid = {
    actor: { active: true, role: 'instituteAdmin', instituteId: 'i1' },
    parent: { active: true, role: 'parent' },
    student: { active: true, instituteId: 'i1' },
    institute: { active: true, status: 'active', instituteId: 'i1' },
  };
  assert.doesNotThrow(() => validateLinkSources(valid));
  assert.throws(() => validateLinkSources({ ...valid, parent: { ...valid.parent, active: false } }));
  assert.throws(() => validateLinkSources({ ...valid, student: { ...valid.student, active: false } }));
  assert.throws(() => validateLinkSources({ ...valid, institute: { ...valid.institute, status: 'suspended' } }));
  assert.throws(() => validateLinkSources({ ...valid, actor: { ...valid.actor, instituteId: 'i2' } }));
});

test('existing links are idempotent and reactivation must be explicit', () => {
  assert.equal(validateExistingLink({ existing: null, instituteId: 'i1' }), 'parentLinkCreated');
  assert.equal(validateExistingLink({ existing: { active: true, instituteId: 'i1' }, instituteId: 'i1' }), null);
  assert.throws(() => validateExistingLink({ existing: { active: false, instituteId: 'i1' }, instituteId: 'i1' }));
  assert.equal(validateExistingLink({
    existing: { active: false, instituteId: 'i1' }, instituteId: 'i1', reactivate: true,
  }), 'parentLinkReactivated');
  assert.throws(() => validateExistingLink({
    existing: { active: true, instituteId: 'i2' }, instituteId: 'i1',
  }));
});

test('student projection whitelists safe fields and class IDs', () => {
  const value = studentProjection({
    student: {
      studentId: 's1', instituteId: 'i1', fullName: 'Student',
      studentNumber: 'S-1', grade: '10', active: true,
      primaryParentMobile: '+94770000000', qrTokenHash: 'secret',
    },
    classIds: ['c2', 'c1', 'c1'], sourceVersion: 4,
  });
  assert.deepEqual(value.classIds, ['c1', 'c2']);
  assert.equal(value.qrTokenHash, undefined);
  assert.equal(value.primaryParentMobile, undefined);
});

test('class projection omits teacher contact and archives safely', () => {
  const value = classProjection({
    academicClass: {
      classId: 'c1', instituteId: 'i1', name: 'Math', subject: 'Math',
      grade: '10', roomOrLocation: 'R1', daysOfWeek: ['monday'],
      startTime: '08:00', endTime: '09:00', active: true, status: 'archived',
    },
    teacherDisplayName: 'Teacher', sourceVersion: 2,
  });
  assert.equal(value.active, false);
  assert.equal(value.teacherDisplayName, 'Teacher');
  assert.equal(value.teacherEmail, undefined);
  assert.throws(() => classProjection({
    academicClass: {
      classId: 'c1', instituteId: 'i1', name: 'Math', subject: 'Math',
      grade: '10', roomOrLocation: 'R1', daysOfWeek: ['monday'],
      startTime: '25:00', endTime: '09:00', active: true, status: 'active',
    },
    teacherDisplayName: null, sourceVersion: 3,
  }), /Schedule time/);
});

test('attendance projection accepts only final safe states', () => {
  const value = attendanceProjection({
    record: {
      summaryId: 's1_2026-08-02_c1', studentId: 's1', instituteId: 'i1',
      classId: 'c1', attendanceDate: new Date(), status: 'late',
      entryTime: new Date(), exitTime: null, late: true,
      currentPresenceState: 'inside', correctionReason: 'private',
    },
    sourceVersion: 3,
  });
  assert.equal(value.status, 'late');
  assert.equal(value.correctionReason, undefined);
  assert.throws(() => attendanceProjection({ record: { ...value, status: 'invented' }, sourceVersion: 4 }));
  assert.throws(() => attendanceProjection({
    record: { ...value, attendanceDate: null }, sourceVersion: 4,
  }), /Attendance date/);
});

test('notice targets and length are validated', () => {
  const base = {
    noticeId: 'n1', instituteId: 'i1', title: 'Notice', message: 'Message',
    priority: 'normal', publishedAt: new Date(), active: true,
    targetType: 'student', targetStudentIds: ['s1'], targetClassIds: [],
  };
  assert.equal(noticeProjection({ notice: base, sourceVersion: 1 }).targetStudentIds[0], 's1');
  assert.throws(() => noticeProjection({ notice: { ...base, targetStudentIds: [] }, sourceVersion: 1 }));
  assert.throws(() => noticeProjection({ notice: { ...base, message: 'x'.repeat(1201) }, sourceVersion: 1 }));
});

test('institute projection copies public fields only', () => {
  const value = institutePublicProjection({
    institute: {
      instituteId: 'i1', name: 'Institute', status: 'active',
      publicPhone: '+9411', smsUsedThisMonth: 99, allowPaidExtraSms: true,
    },
    sourceVersion: 1,
  });
  assert.equal(value.displayName, 'Institute');
  assert.equal(value.smsUsedThisMonth, undefined);
});

test('audit payload has no personal values or secrets', () => {
  const value = safeAuditPayload({
    auditLogId: 'a1', actorUid: 'admin', instituteId: 'i1',
    action: 'parentLinkCreated', targetType: 'student', targetId: 's1',
  });
  assert.equal(value.password, undefined);
  assert.equal(value.parentUid, undefined);
});
