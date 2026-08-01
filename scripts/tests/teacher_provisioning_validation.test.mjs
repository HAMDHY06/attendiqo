import assert from 'node:assert/strict';
import test from 'node:test';
import {
  defaultTeacherPermissions,
  meetsPasswordPolicy,
  normalizeEmployeeNumber,
  validateTeacherInput,
} from '../lib/teacher_provisioning_validation.mjs';

test('normalizes and validates teacher input', () => {
  const result = validateTeacherInput({
    instituteId: 'institute-a',
    displayName: 'Teacher One',
    email: ' TEACHER@EXAMPLE.COM ',
    employeeNumber: ' emp-01 ', phoneNumber: ' +94 77 123 4567 ',
  });
  assert.deepEqual(result, {
    email: 'teacher@example.com',
    employeeNumber: 'EMP-01',
    phoneNumber: '+94 77 123 4567',
  });
});

test('rejects unsafe employee numbers and invalid emails', () => {
  assert.throws(() => validateTeacherInput({
    instituteId: 'institute-a', displayName: 'Teacher',
    email: 'invalid', employeeNumber: 'bad value',
  }));
  assert.equal(normalizeEmployeeNumber(''), null);
  assert.throws(() => validateTeacherInput({
    instituteId: 'institute-a', displayName: 'Teacher',
    email: 'teacher@example.com', phoneNumber: 'not-a-phone',
  }));
});

test('default permissions are least privilege and complete', () => {
  assert.equal(Object.keys(defaultTeacherPermissions).length, 10);
  assert.equal(defaultTeacherPermissions.canTakeAttendance, true);
  assert.equal(defaultTeacherPermissions.canCreateClasses, false);
  assert.equal(defaultTeacherPermissions.canSendManualNotifications, false);
});

test('password policy requires every character category', () => {
  assert.equal(meetsPasswordPolicy('SecurePass2!Value'), true);
  assert.equal(meetsPasswordPolicy('alllowercase2!'), false);
  assert.equal(meetsPasswordPolicy('NoSpecial123'), false);
});
