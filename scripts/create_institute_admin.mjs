import process from 'node:process';
import { randomInt } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const expectedProject = 'attendiqo-system';
const confirmation = `--confirm-project=${expectedProject}`;
const actorArgument = process.argv.find((value) => value.startsWith('--actor-uid='));
const actorUid = actorArgument?.slice('--actor-uid='.length).trim();

if (!process.argv.includes(confirmation) || !actorUid) {
  throw new Error(
    `Refusing to run. Pass ${confirmation} and --actor-uid=<verified-super-admin-uid>.`,
  );
}
if (!process.stdin.isTTY || !process.stdout.isTTY) {
  throw new Error('Provisioning requires an interactive terminal.');
}

const prompt = createInterface({ input: process.stdin, output: process.stdout });
const instituteId = (await prompt.question('Existing institute ID: ')).trim();
const displayName = (await prompt.question('Institute Admin display name: ')).trim();
const email = (await prompt.question('Institute Admin email: ')).trim().toLowerCase();
prompt.close();

if (!instituteId || !displayName) throw new Error('Institute ID and display name are required.');
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Invalid email address.');

const app = getApps()[0] ?? initializeApp({
  credential: applicationDefault(),
  projectId: expectedProject,
});
const auth = getAuth(app);
const firestore = getFirestore(app);

const [actor, actorProfile, instituteSnapshot] = await Promise.all([
  auth.getUser(actorUid),
  firestore.collection('users').doc(actorUid).get(),
  firestore.collection('institutes').doc(instituteId).get(),
]);
if (actor.customClaims?.superAdmin !== true
    || actorProfile.data()?.role !== 'superAdmin'
    || actorProfile.data()?.active !== true) {
  throw new Error('The actor is not an active, verified Super Admin.');
}
if (!instituteSnapshot.exists) throw new Error('The selected institute does not exist.');

try {
  await auth.getUserByEmail(email);
  throw new Error('An Authentication account already uses that email.');
} catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
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

let createdUser;
try {
  createdUser = await auth.createUser({
    email,
    displayName,
    password: temporaryPassword,
    disabled: false,
    emailVerified: false,
  });
  await auth.setCustomUserClaims(createdUser.uid, {
    role: 'instituteAdmin',
    instituteId,
  });

  const profileReference = firestore.collection('users').doc(createdUser.uid);
  const auditReference = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    const institute = await transaction.get(
      firestore.collection('institutes').doc(instituteId),
    );
    if (!institute.exists) throw new Error('The selected institute no longer exists.');
    transaction.create(profileReference, {
      uid: createdUser.uid,
      email,
      displayName,
      role: 'instituteAdmin',
      instituteId,
      active: true,
      mustChangePassword: true,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: actorUid,
      updatedAt: FieldValue.serverTimestamp(),
      lastLoginAt: null,
    });
    transaction.create(auditReference, {
      auditLogId: auditReference.id,
      actorUid,
      actorRole: 'superAdmin',
      instituteId,
      action: 'instituteAdminCreated',
      targetType: 'user',
      targetId: createdUser.uid,
      summary: 'Institute Admin account created',
      createdAt: FieldValue.serverTimestamp(),
    });
  });
} catch (error) {
  if (createdUser) await auth.deleteUser(createdUser.uid).catch(() => undefined);
  temporaryPassword = '';
  throw error;
}

process.stdout.write(`Institute Admin created for UID ${createdUser.uid}.\n`);
process.stdout.write('Copy the temporary password now; it will never be shown again:\n');
process.stdout.write(`${temporaryPassword}\n`);
temporaryPassword = '';
