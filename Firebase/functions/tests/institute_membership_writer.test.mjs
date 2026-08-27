import test from 'node:test';
import assert from 'node:assert/strict';
import { approveInstituteJoinRequest, submitInstituteJoinRequest } from '../lib/institute_membership_writer.mjs';

const database = (seed = {}) => {
  const values = new Map(Object.entries(seed));
  const ref = (path) => ({
    path,
    id: path.split('/').at(-1),
    get: async () => ({ exists: values.has(path), data: () => values.get(path) }),
  });
  const firestore = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    runTransaction: (fn) => fn({
      get: async (document) => ({ exists: values.has(document.path), data: () => values.get(document.path) }),
      set: (document, value, options) => values.set(document.path, options?.merge ? { ...values.get(document.path), ...value } : value),
      update: (document, value) => values.set(document.path, { ...values.get(document.path), ...value }),
    }),
  };
  return { firestore, values };
};

test('a join code creates only an idempotent pending request', async () => {
  const { firestore, values } = database({
    'institute_join_codes/DEMO-2026': { instituteId: 'institute-a', active: true },
    'institutes/institute-a': { active: true, status: 'active' },
  });
  const result = await submitInstituteJoinRequest({ firestore, uid: 'teacher-a', data: { joinCode: 'demo-2026', requestedRole: 'teacher' } });
  assert.equal(result.status, 'pending');
  assert.equal(values.get('institute_join_requests/teacher-a_institute-a_teacher').status, 'pending');
  await assert.rejects(() => submitInstituteJoinRequest({ firestore, uid: 'teacher-a', data: { joinCode: 'DEMO-2026', requestedRole: 'superAdmin' } }));
});

test('only a verified Super Admin can activate an Institute Admin request', async () => {
  const { firestore, values } = database({
    'institute_join_requests/user-a_institute-a_instituteAdmin': { uid: 'user-a', instituteId: 'institute-a', requestedRole: 'instituteAdmin', status: 'pending' },
  });
  await assert.rejects(() => approveInstituteJoinRequest({ firestore, uid: 'admin-a', role: 'instituteAdmin', instituteId: 'institute-a', claims: {}, data: { requestId: 'user-a_institute-a_instituteAdmin' } }));
  await approveInstituteJoinRequest({ firestore, uid: 'super-a', role: 'superAdmin', instituteId: null, claims: { superAdmin: true }, data: { requestId: 'user-a_institute-a_instituteAdmin' } });
  assert.equal(values.get('institute_memberships/user-a_institute-a').role, 'instituteAdmin');
});

test('same-institute Institute Admin can activate a Teacher request', async () => {
  const { firestore } = database({
    'institute_join_requests/teacher-a_institute-a_teacher': { uid: 'teacher-a', instituteId: 'institute-a', requestedRole: 'teacher', status: 'pending' },
  });
  const result = await approveInstituteJoinRequest({ firestore, uid: 'admin-a', role: 'instituteAdmin', instituteId: 'institute-a', claims: {}, data: { requestId: 'teacher-a_institute-a_teacher' } });
  assert.equal(result.status, 'active');
});
