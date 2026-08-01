import process from 'node:process';
import { createInterface } from 'node:readline/promises';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const expectedProject = 'attendiqo-system';
if (!process.argv.includes(`--confirm-project=${expectedProject}`)) {
  throw new Error(`Refusing to run. Pass --confirm-project=${expectedProject} after verifying your Admin credentials.`);
}
if (!process.stdin.isTTY || !process.stdout.isTTY) {
  throw new Error('Provisioning requires an interactive terminal. Do not pipe credentials.');
}

const prompt = (question, { hidden = false } = {}) => new Promise((resolve, reject) => {
  process.stdout.write(question);
  let value = '';
  const wasRaw = process.stdin.isRaw;
  process.stdin.setEncoding('utf8');
  process.stdin.resume();
  if (hidden) process.stdin.setRawMode(true);
  const onData = (character) => {
    if (character === '\u0003') {
      cleanup();
      reject(new Error('Provisioning cancelled.'));
      return;
    }
    if (character === '\r' || character === '\n') {
      process.stdout.write('\n');
      cleanup();
      resolve(value.trim());
      return;
    }
    if (character === '\u007f' || character === '\b') {
      value = value.slice(0, -1);
      return;
    }
    value += character;
  };
  const cleanup = () => {
    process.stdin.off('data', onData);
    if (hidden) process.stdin.setRawMode(Boolean(wasRaw));
    process.stdin.pause();
  };
  process.stdin.on('data', onData);
});

const emailPrompt = createInterface({ input: process.stdin, output: process.stdout });
const email = (await emailPrompt.question('Super Admin email: ')).trim().toLowerCase();
emailPrompt.close();
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Invalid email address.');

const app = getApps()[0] ?? initializeApp({ credential: applicationDefault(), projectId: expectedProject });
const auth = getAuth(app);
const firestore = getFirestore(app);

let user;
try {
  user = await auth.getUserByEmail(email);
} catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
  let password = await prompt('Initial password (hidden, 10+ chars with upper/lower/number/special): ', { hidden: true });
  if (password.length < 10 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password) || !/[^A-Za-z0-9]/.test(password)) {
    password = '';
    throw new Error('Password does not meet the Attendiqo password policy.');
  }
  user = await auth.createUser({ email, password, emailVerified: false, disabled: false });
  password = '';
}

const reference = firestore.collection('users').doc(user.uid);
const existing = await reference.get();
if (existing.exists && existing.data().role && existing.data().role !== 'superAdmin') {
  throw new Error('Refusing to replace an existing non-Super-Admin profile.');
}

await auth.setCustomUserClaims(user.uid, { ...(user.customClaims ?? {}), superAdmin: true });
await reference.set({
  uid: user.uid,
  email,
  displayName: existing.data()?.displayName ?? 'HamdhyTech Super Admin',
  role: 'superAdmin',
  instituteId: null,
  active: true,
  mustChangePassword: !existing.exists,
  createdAt: existing.data()?.createdAt ?? FieldValue.serverTimestamp(),
  createdBy: existing.data()?.createdBy ?? 'one-time-super-admin-provisioner',
  updatedAt: FieldValue.serverTimestamp(),
  lastLoginAt: existing.data()?.lastLoginAt ?? null,
}, { merge: true });

process.stdout.write(`Super Admin provisioning completed for UID ${user.uid}. No password was logged or saved.\n`);
