import test from 'node:test';
import assert from 'node:assert/strict';

import {
  TEACHER_PERMISSIONS,
  authorizeInstituteActor,
  authorizeTeacherClassAction,
  hasExactTeacherPermissions,
} from '../lib/role_authorization.mjs';

const permissions = Object.fromEntries(TEACHER_PERMISSIONS.map(key => [key, false]));
const institute = { instituteId: 'institute-a', active: true, status: 'active' };
const academicClass = {
  classId: 'class-a', instituteId: 'institute-a', status: 'active', teacherIds: ['teacher-a'],
};

test('backend permission map rejects missing and unknown fields', () => {
  assert.equal(hasExactTeacherPermissions(permissions), true);
  assert.equal(hasExactTeacherPermissions({ ...permissions, unknown: true }), false);
  const { canCreateClasses, ...missing } = permissions;
  assert.equal(canCreateClasses, false);
  assert.equal(hasExactTeacherPermissions(missing), false);
});

test('Institute Admin backend scope is full only for own active institute', () => {
  const actor = { uid: 'admin-a', role: 'instituteAdmin', instituteId: 'institute-a', active: true };
  assert.equal(authorizeInstituteActor({ actor, institute, targetInstituteId: 'institute-a' }), true);
  assert.equal(authorizeInstituteActor({ actor, institute, targetInstituteId: 'institute-b' }), false);
  assert.equal(authorizeInstituteActor({ actor, institute: { ...institute, active: false }, targetInstituteId: 'institute-a' }), false);
});

test('Teacher backend checks permission, assignment, institute and backend state', () => {
  const actor = {
    uid: 'teacher-a', role: 'teacher', instituteId: 'institute-a', active: true,
    permissions: { ...permissions, canTakeAttendance: true, canCreateClasses: true },
  };
  assert.equal(authorizeTeacherClassAction({ actor, institute, academicClass, permission: 'canTakeAttendance' }), true);
  assert.equal(authorizeTeacherClassAction({ actor, institute, academicClass: { ...academicClass, teacherIds: [] }, permission: 'canTakeAttendance' }), false);
  assert.equal(authorizeTeacherClassAction({ actor, institute, academicClass, permission: 'canCorrectAttendance' }), false);
  assert.equal(authorizeTeacherClassAction({ actor, institute, permission: 'canCreateClasses', creating: true }), true);
  assert.equal(authorizeTeacherClassAction({ actor, institute, academicClass, permission: 'canTakeAttendance', backendAvailable: false }), false);
});

test('Firestore role field alone never verifies Super Admin backend access', () => {
  const fake = { uid: 'fake', role: 'superAdmin', active: true };
  const verified = { ...fake, verifiedSuperAdminClaim: true };
  assert.equal(authorizeInstituteActor({ actor: fake, institute, targetInstituteId: 'institute-a' }), false);
  assert.equal(authorizeInstituteActor({ actor: verified, institute, targetInstituteId: 'institute-a' }), true);
});
