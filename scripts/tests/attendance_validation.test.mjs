import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceRecordId, authorizeAttendanceActor, hashQrPayload, validateAttendanceInput } from '../lib/attendance_validation.mjs';
import { TEACHER_PERMISSIONS } from '../lib/role_authorization.mjs';

test('QR payload validation returns a hash without exposing the raw token', () => {
  const payload = `attendiqo://student/${'a'.repeat(43)}`;
  const hash = hashQrPayload(payload);
  assert.equal(hash.length, 64);
  assert.equal(hash.includes('a'.repeat(43)), false);
  assert.equal(hashQrPayload('student-id'), null);
});

test('attendance input rejects unsupported modes and device values', () => {
  const qrPayload = `attendiqo://student/${'b'.repeat(43)}`;
  assert.throws(() => validateAttendanceInput({ sessionId: 's', mode: 'invalid', deviceId: 'd', qrPayload }), /invalid-mode/);
  assert.throws(() => validateAttendanceInput({ sessionId: 's', mode: 'entry', deviceId: '', qrPayload }), /invalid-device/);
  assert.equal(validateAttendanceInput({ sessionId: 's', mode: 'entry', deviceId: 'd', qrPayload }).sessionId, 's');
});

test('actor authorization requires claims, institute isolation, assignment, and permission', () => {
  const academicClass = { instituteId: 'i1', teacherIds: ['teacher-a'] };
  const institute = { instituteId: 'i1', active: true, status: 'active' };
  const permissions = Object.fromEntries(TEACHER_PERMISSIONS.map(key => [key, key === 'canTakeAttendance']));
  assert.equal(authorizeAttendanceActor({ actor: { uid: 'super', role: 'superAdmin', active: true, verifiedSuperAdminClaim: false }, academicClass, institute }), false);
  assert.equal(authorizeAttendanceActor({ actor: { uid: 'super', role: 'superAdmin', active: true, verifiedSuperAdminClaim: true }, academicClass, institute }), true);
  assert.equal(authorizeAttendanceActor({ actor: { uid: 'teacher-a', role: 'teacher', active: true, instituteId: 'i1', permissions }, academicClass, institute }), true);
  assert.equal(authorizeAttendanceActor({ actor: { uid: 'teacher-b', role: 'teacher', active: true, instituteId: 'i1', permissions }, academicClass, institute }), false);
  assert.equal(authorizeAttendanceActor({ actor: { uid: 'teacher-a', role: 'teacher', active: true, instituteId: 'i2', permissions }, academicClass, institute }), false);
});

test('attendance identity is session-specific', () => {
  assert.notEqual(attendanceRecordId('english-2026-08-03', 'student-a'), attendanceRecordId('science-2026-08-03', 'student-a'));
});
