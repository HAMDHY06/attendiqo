import { AppError, safeHash, type AuthenticatedUser } from './security';
import { mintAccessToken, parseAccount, type WorkerFirestoreAdmin } from './worker-firestore-admin';

type Json = Record<string, unknown>;
const projectId = 'attendiqo-system';
const packages = new Set(['com.hamdhytech.attendiqo', 'com.hamdhytech.attendiqo.connect']);
const permissionStates = new Set(['granted', 'denied', 'unknown']);

function exact(value: Json, fields: string[]) {
  for (const key of Object.keys(value)) if (!fields.includes(key)) throw new AppError(400, 'unknown_field', 'The request contains an unsupported field.');
}

function text(value: unknown, field: string, max: number): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new AppError(400, 'invalid_payload', `The ${field} is invalid.`);
  return value.trim();
}

export async function registerNotificationDevice(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
): Promise<Json> {
  exact(payload, ['token', 'appPackage', 'platform', 'appVersion', 'deviceHash', 'permissionStatus', 'oldTokenId']);
  const token = text(payload.token, 'token', 4096);
  const appPackage = text(payload.appPackage, 'appPackage', 100);
  const platform = text(payload.platform, 'platform', 20);
  const appVersion = text(payload.appVersion, 'appVersion', 40);
  const deviceHash = text(payload.deviceHash, 'deviceHash', 64);
  const permissionStatus = text(payload.permissionStatus, 'permissionStatus', 20);
  const oldTokenId = payload.oldTokenId == null ? undefined : text(payload.oldTokenId, 'oldTokenId', 128);
  if (!packages.has(appPackage) || platform !== 'android' || !permissionStates.has(permissionStatus)) {
    throw new AppError(400, 'invalid_payload', 'The notification device details are invalid.');
  }
  const expectedHash = await safeHash(`${appPackage}:${token}`);
  if (deviceHash !== expectedHash) throw new AppError(400, 'invalid_device_hash', 'The notification device could not be verified.');
  const tokenId = `${user.uid}_${expectedHash.slice(0, 32)}`;
  const now = new Date().toISOString();
  const existing = await firestore.get(`notification_tokens/${tokenId}`);
  const writes: Array<{ path: string; fields: Json; updateTime?: string; createOnly?: boolean }> = [{
    path: `notification_tokens/${tokenId}`,
    updateTime: existing?.updateTime,
    createOnly: !existing,
    fields: { tokenId, uid: user.uid, token, tokenHash: expectedHash, appPackage, platform, appVersion, permissionStatus, active: permissionStatus === 'granted', createdAt: existing?.fields.createdAt ?? now, updatedAt: now },
  }];
  if (oldTokenId && oldTokenId !== tokenId) {
    const old = await firestore.get(`notification_tokens/${oldTokenId}`);
    if (old?.fields.uid === user.uid) writes.push({ path: `notification_tokens/${oldTokenId}`, updateTime: old.updateTime, fields: { ...old.fields, active: false, updatedAt: now } });
  }
  await firestore.commit(writes);
  return { tokenId };
}

export async function deactivateNotificationDevice(
  firestore: WorkerFirestoreAdmin,
  user: AuthenticatedUser,
  payload: Json,
): Promise<Json> {
  exact(payload, ['tokenId']);
  const tokenId = text(payload.tokenId, 'tokenId', 128);
  const existing = await firestore.get(`notification_tokens/${tokenId}`);
  if (!existing || existing.fields.uid !== user.uid) return { status: 'inactive' };
  await firestore.commit([{ path: `notification_tokens/${tokenId}`, updateTime: existing.updateTime, fields: { ...existing.fields, active: false, updatedAt: new Date().toISOString() } }]);
  return { status: 'inactive' };
}

export function createAttendanceNotifier(
  firestore: WorkerFirestoreAdmin,
  serviceAccountJson: string,
  requestFetch: typeof fetch = fetch,
  signedAssertionProvider?: () => Promise<string>,
) {
  const account = parseAccount(serviceAccountJson);
  return async (event: { studentId: string; status: string; mode?: string }): Promise<void> => {
    const links = (await firestore.queryParentLinksByStudent(event.studentId)).filter((link) => link.fields.active === true);
    const parentUids = [...new Set(links.map((link) => link.fields.parentUid).filter((uid): uid is string => typeof uid === 'string'))];
    if (parentUids.length === 0) return;
    const student = await firestore.get(`students/${event.studentId}`);
    const studentName = typeof student?.fields.fullName === 'string' ? student.fields.fullName : 'Your child';
    const title = event.mode === 'departure' ? 'Departure recorded' : event.status === 'absent' ? 'Absence recorded' : event.status === 'late' ? 'Late arrival recorded' : 'Attendance recorded';
    const body = event.mode === 'departure' ? `${studentName} has left.` : `${studentName} was marked ${event.status}.`;
    const tokenDocs = (await Promise.all(parentUids.map((uid) => firestore.queryNotificationTokens(uid)))).flat();
    const tokens = tokenDocs.filter((doc) => doc.fields.active === true && doc.fields.permissionStatus === 'granted' && typeof doc.fields.token === 'string');
    if (tokens.length === 0) return;
    const accessToken = await mintAccessToken(account, requestFetch, signedAssertionProvider, 'https://www.googleapis.com/auth/firebase.messaging');
    await Promise.all(tokens.map(async (doc) => {
      const response = await requestFetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
        body: JSON.stringify({ message: { token: doc.fields.token, notification: { title, body }, data: { destination: 'attendance' }, android: { priority: 'high' } } }),
      });
      if (!response.ok && (response.status === 404 || response.status === 400)) {
        await firestore.commit([{ path: `notification_tokens/${doc.fields.tokenId}`, updateTime: doc.updateTime, fields: { ...doc.fields, active: false, updatedAt: new Date().toISOString() } }]).catch(() => undefined);
      }
    }));
  };
}
