import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

const projectId = 'attendiqo-system';
let environment;

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
  lastLoginAt: null,
});

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const records = [
      profile({ uid: 'parent-a', role: 'parent' }),
      profile({ uid: 'teacher-a', role: 'teacher', instituteId: 'institute-a' }),
      profile({ uid: 'teacher-b', role: 'teacher', instituteId: 'institute-b' }),
      profile({ uid: 'inactive-teacher', role: 'teacher', instituteId: 'institute-a', active: false }),
      profile({ uid: 'temporary-teacher', role: 'teacher', instituteId: 'institute-a', mustChangePassword: true }),
      profile({ uid: 'admin-a', role: 'instituteAdmin', instituteId: 'institute-a' }),
      profile({ uid: 'fake-super', role: 'superAdmin' }),
      profile({ uid: 'real-super', role: 'superAdmin' }),
    ];
    for (const record of records) {
      await setDoc(doc(context.firestore(), 'users', record.uid), record);
    }
  });
});

after(async () => environment.cleanup());

test('unauthenticated users cannot read profiles', async () => {
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'users', 'teacher-a')));
});

test('user can read own profile', async () => {
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-a')));
});

test('user cannot change own role', async () => {
  await assertFails(updateDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-a'), { role: 'superAdmin' }));
});

test('user can update last login and clear a required password change', async () => {
  const firestore = environment.authenticatedContext('temporary-teacher').firestore();
  const reference = doc(firestore, 'users', 'temporary-teacher');
  await assertSucceeds(updateDoc(reference, {
    mustChangePassword: false,
    lastLoginAt: new Date('2026-08-01T08:00:00Z'),
    updatedAt: new Date('2026-08-01T08:00:00Z'),
  }));
});

test('user cannot change own institute or activate itself', async () => {
  const reference = doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-a');
  await assertFails(updateDoc(reference, { instituteId: 'institute-b' }));
  const inactive = doc(environment.authenticatedContext('inactive-teacher').firestore(), 'users', 'inactive-teacher');
  await assertFails(updateDoc(inactive, { active: true }));
});

test('parent cannot access a teacher profile', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('parent-a').firestore(), 'users', 'teacher-a')));
});

test('teacher cannot access another institute profile', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('teacher-a').firestore(), 'users', 'teacher-b')));
});

test('Firestore role field alone does not grant Super Admin access', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('fake-super').firestore(), 'users', 'teacher-a')));
});

test('verified Super Admin custom claim can read profiles', async () => {
  const firestore = environment.authenticatedContext('real-super', { superAdmin: true }).firestore();
  const snapshot = await assertSucceeds(getDoc(doc(firestore, 'users', 'teacher-b')));
  assert.equal(snapshot.data().role, 'teacher');
});

test('Institute Admin is isolated to management profiles in own institute', async () => {
  const firestore = environment.authenticatedContext('admin-a').firestore();
  await assertSucceeds(getDoc(doc(firestore, 'users', 'teacher-a')));
  await assertFails(getDoc(doc(firestore, 'users', 'teacher-b')));
  await assertFails(getDoc(doc(firestore, 'users', 'parent-a')));
});

test('all unrelated collections remain denied', async () => {
  await assertFails(getDoc(doc(environment.authenticatedContext('real-super', { superAdmin: true }).firestore(), 'institutes', 'institute-a')));
});
