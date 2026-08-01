import process from 'node:process';
import { randomInt } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import {
  defaultTeacherPermissions,
  meetsPasswordPolicy,
  validateTeacherInput,
} from './lib/teacher_provisioning_validation.mjs';

const expectedProject = 'attendiqo-system';
const confirmation = `--confirm-project=${expectedProject}`;
const actorArgument = process.argv.find((value) => value.startsWith('--actor-uid='));
const actorUid = actorArgument?.slice('--actor-uid='.length).trim();
if (!process.argv.includes(confirmation) || !actorUid) {
  throw new Error(`Refusing to run. Pass ${confirmation} and --actor-uid=<uid>.`);
}
if (!process.stdin.isTTY || !process.stdout.isTTY) {
  throw new Error('Teacher provisioning requires an interactive terminal.');
}

const prompt = createInterface({ input: process.stdin, output: process.stdout });
const instituteId = (await prompt.question('Existing active institute ID: ')).trim();
const displayName = (await prompt.question('Teacher display name: ')).trim();
const emailInput = await prompt.question('Teacher email: ');
const phoneInput = (await prompt.question('Optional phone number: ')).trim();
const employeeInput = await prompt.question('Optional employee number: ');
prompt.close();
const { email, employeeNumber, phoneNumber } = validateTeacherInput({
  instituteId, displayName, email: emailInput, employeeNumber: employeeInput,
  phoneNumber: phoneInput,
});

const app = getApps()[0] ?? initializeApp({
  credential: applicationDefault(), projectId: expectedProject,
});
const auth = getAuth(app);
const firestore = getFirestore(app);
const [actorAccount, actorProfileSnapshot, instituteSnapshot] = await Promise.all([
  auth.getUser(actorUid),
  firestore.collection('users').doc(actorUid).get(),
  firestore.collection('institutes').doc(instituteId).get(),
]);
const actor = actorProfileSnapshot.data();
const verifiedSuperAdmin = actorAccount.customClaims?.superAdmin === true
  && actor?.role === 'superAdmin' && actor?.active === true;
const activeInstituteAdmin = actor?.role === 'instituteAdmin'
  && actor?.active === true && actor?.instituteId === instituteId
  && actorAccount.customClaims?.role === 'instituteAdmin'
  && actorAccount.customClaims?.instituteId === instituteId;
if (!verifiedSuperAdmin && !activeInstituteAdmin) {
  throw new Error('Actor must be an active same-institute Admin or verified Super Admin.');
}
const institute = instituteSnapshot.data();
if (!instituteSnapshot.exists || institute?.active !== true || institute?.status !== 'active') {
  throw new Error('Target institute does not exist or is not active.');
}
try {
  await auth.getUserByEmail(email);
  throw new Error('An Authentication account already uses that email.');
} catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
}

const reservationId = employeeNumber ? `${instituteId}_${employeeNumber}` : null;
if (reservationId && (await firestore.collection('teacher_employee_numbers').doc(reservationId).get()).exists) {
  throw new Error('That employee number is already used in this institute.');
}
const pick = (characters) => characters[randomInt(characters.length)];
const shuffle = (values) => {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const swap = randomInt(index + 1);
    [values[index], values[swap]] = [values[swap], values[index]];
  }
  return values.join('');
};
const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const lowercase = 'abcdefghijkmnopqrstuvwxyz';
const digits = '23456789';
const specials = '!@#%';
const all = `${uppercase}${lowercase}${digits}${specials}`;
let temporaryPassword = shuffle([
  pick(uppercase), pick(lowercase), pick(digits), pick(specials),
  ...Array.from({ length: 12 }, () => pick(all)),
]);
if (!meetsPasswordPolicy(temporaryPassword)) throw new Error('Password generator policy failure.');

let createdUser;
try {
  createdUser = await auth.createUser({
    email, displayName, password: temporaryPassword, disabled: false, emailVerified: false,
  });
  await auth.setCustomUserClaims(createdUser.uid, { role: 'teacher', instituteId });
  const profileReference = firestore.collection('users').doc(createdUser.uid);
  const reservationReference = reservationId
    ? firestore.collection('teacher_employee_numbers').doc(reservationId)
    : null;
  const auditReference = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    const freshSnapshots = await Promise.all([
      transaction.get(firestore.collection('users').doc(actorUid)),
      transaction.get(firestore.collection('institutes').doc(instituteId)),
      ...(reservationReference ? [transaction.get(reservationReference)] : []),
    ]);
    const freshActor = freshSnapshots[0].data();
    const freshInstitute = freshSnapshots[1].data();
    const actorStillAllowed = (verifiedSuperAdmin && freshActor?.active === true)
      || (freshActor?.role === 'instituteAdmin'
        && freshActor?.active === true && freshActor?.instituteId === instituteId);
    if (!actorStillAllowed) throw new Error('Actor is no longer authorized.');
    if (freshInstitute?.active !== true || freshInstitute?.status !== 'active') {
      throw new Error('Institute is no longer active.');
    }
    if (reservationReference && freshSnapshots[2].exists) {
      throw new Error('Employee number was reserved concurrently.');
    }
    transaction.create(profileReference, {
      uid: createdUser.uid, email, displayName, role: 'teacher', instituteId,
      active: true, mustChangePassword: true,
      createdAt: FieldValue.serverTimestamp(), createdBy: actorUid,
      updatedAt: FieldValue.serverTimestamp(), updatedBy: actorUid,
      lastLoginAt: null, phoneNumber, employeeNumber,
      permissions: defaultTeacherPermissions, status: 'pendingFirstLogin',
    });
    if (reservationReference) transaction.create(reservationReference, {
      instituteId, employeeNumber, teacherUid: createdUser.uid,
      createdAt: FieldValue.serverTimestamp(), createdBy: actorUid,
    });
    transaction.create(auditReference, {
      auditLogId: auditReference.id, actorUid,
      actorRole: verifiedSuperAdmin ? 'superAdmin' : 'instituteAdmin',
      instituteId, action: 'teacherCreated', targetType: 'teacher',
      targetId: createdUser.uid, summary: 'Teacher account created',
      createdAt: FieldValue.serverTimestamp(),
    });
  });
} catch (error) {
  if (createdUser) await auth.deleteUser(createdUser.uid).catch(() => undefined);
  temporaryPassword = '';
  throw error;
}

process.stdout.write(`Teacher created for UID ${createdUser.uid}.\n`);
process.stdout.write('Copy the temporary password now; it will never be shown again:\n');
process.stdout.write(`${temporaryPassword}\n`);
temporaryPassword = '';
