import { AppError, type FirestoreDocument } from './security';

type Json = Record<string, unknown>;
type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const projectId = 'attendiqo-system';

// The Worker service account has broad datastore IAM at Google. This local
// allowlist is a second mandatory boundary: no handler can use it for an
// arbitrary collection, path, query, or field payload.
const readableCollections = new Set([
  'users',
  'institutes',
  'institute_join_codes',
  'institute_join_requests',
  'institute_memberships',
  'students',
  'student_sms_consents',
]);
const writableCollections = new Set([
  'institute_join_requests',
  'institute_memberships',
  'audit_logs',
]);

function base64Url(bytes: Uint8Array): string {
  let raw = '';
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function text64(value: string): string {
  return base64Url(new TextEncoder().encode(value));
}

function assertPath(path: string, writable = false): void {
  const parts = path.split('/');
  if (parts.length !== 2 || !/^[A-Za-z0-9_-]{1,128}$/.test(parts[0]) || !/^[A-Za-z0-9_-]{1,256}$/.test(parts[1])) {
    throw new AppError(400, 'invalid_path', 'The request is invalid.');
  }
  const collections = writable ? writableCollections : readableCollections;
  if (!collections.has(parts[0])) throw new AppError(403, 'forbidden_scope', 'The request is not permitted.');
}

function decodeValue(value: unknown): unknown {
  if (!value || typeof value !== 'object') return undefined;
  const item = value as Json;
  if ('stringValue' in item) return item.stringValue;
  if ('booleanValue' in item) return item.booleanValue;
  if ('integerValue' in item) return Number(item.integerValue);
  if ('doubleValue' in item) return item.doubleValue;
  if ('timestampValue' in item) return item.timestampValue;
  if ('arrayValue' in item) {
    const values = (item.arrayValue as { values?: unknown[] }).values ?? [];
    return values.map(decodeValue);
  }
  if ('mapValue' in item) {
    const fields = (item.mapValue as { fields?: Record<string, unknown> }).fields ?? {};
    return Object.fromEntries(Object.entries(fields).map(([key, field]) => [key, decodeValue(field)]));
  }
  return undefined;
}

function encodeValue(value: unknown): Json {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number' && Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === 'number' && Number.isFinite(value)) return { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (value && typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value as Json).map(([key, item]) => [key, encodeValue(item)])) } };
  }
  throw new AppError(400, 'invalid_payload', 'The request is invalid.');
}

function encodeFields(fields: Json): Record<string, Json> {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, encodeValue(value)]));
}

function parseAccount(raw: string): ServiceAccount {
  try {
    const value = JSON.parse(raw) as Partial<ServiceAccount>;
    if (value.project_id !== projectId || typeof value.client_email !== 'string' || !value.client_email.endsWith('.gserviceaccount.com') || typeof value.private_key !== 'string' || !value.private_key.includes('BEGIN PRIVATE KEY')) {
      throw new Error('invalid');
    }
    return value as ServiceAccount;
  } catch {
    throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
  }
}

async function mintAccessToken(
  account: ServiceAccount,
  requestFetch: typeof fetch,
  signedAssertionProvider?: () => Promise<string>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = text64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = text64(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 300,
  }));
  const assertion = signedAssertionProvider
    ? await signedAssertionProvider()
    : await (async () => {
        const keyMaterial = account.private_key
          .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
          .replace(/\s/g, '')
          .replace(/-/g, '+')
          .replace(/_/g, '/');
        const keyBytes = Uint8Array.from(
          atob(keyMaterial + '='.repeat((4 - (keyMaterial.length % 4)) % 4)),
          (value) => value.charCodeAt(0),
        );
        const key = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
          .catch(() => { throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.'); });
        const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
        return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
      })();
  const response = await requestFetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  });
  const result: { access_token?: string } = await response
    .json<{ access_token?: string }>()
    .catch(() => ({}));
  if (!response.ok || typeof result.access_token !== 'string' || result.access_token.length < 20) {
    throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
  }
  return result.access_token;
}

export type WorkerFirestoreAdmin = {
  get(path: string): Promise<FirestoreDocument | undefined>;
  queryMemberships(uid: string): Promise<FirestoreDocument[]>;
  queryJoinRequests(field: 'uid' | 'instituteId', value: string): Promise<FirestoreDocument[]>;
  queryPendingInstituteAdminRequests(): Promise<FirestoreDocument[]>;
  commit(writes: Array<{ path: string; fields: Json; updateTime?: string; createOnly?: boolean }>): Promise<void>;
};

export function createWorkerFirestoreAdmin(
  serviceAccountJson: string,
  requestFetch: typeof fetch = fetch,
  testOnly?: { signedAssertionProvider?: () => Promise<string> },
): WorkerFirestoreAdmin {
  // Parse the backend-only credential lazily. Token verification is independent
  // of Firestore access, so malformed or expired bearer tokens must receive a
  // safe authentication error rather than being masked by backend credential
  // availability.
  let account: ServiceAccount | undefined;
  const serviceAccount = (): ServiceAccount => account ??= parseAccount(serviceAccountJson);

  async function authorizedFetch(path: string, init?: RequestInit): Promise<Response> {
    const accessToken = await mintAccessToken(serviceAccount(), requestFetch, testOnly?.signedAssertionProvider);
    return requestFetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents${path}`, {
      ...init,
      headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json', ...(init?.headers ?? {}) },
    });
  }

  return {
    async get(path) {
      assertPath(path);
      const response = await authorizedFetch(`/${path}`);
      if (response.status === 404) return undefined;
      if (!response.ok) throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
      const document = await response.json<{ fields?: Record<string, unknown>; updateTime?: string }>();
      return {
        fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)])),
        updateTime: document.updateTime,
      } as FirestoreDocument;
    },
    async queryMemberships(uid) {
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
        throw new AppError(400, 'invalid_path', 'The request is invalid.');
      }
      const accessToken = await mintAccessToken(serviceAccount(), requestFetch, testOnly?.signedAssertionProvider);
      const response = await requestFetch(
        `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
          body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'institute_memberships' }], where: { fieldFilter: { field: { fieldPath: 'uid' }, op: 'EQUAL', value: { stringValue: uid } } }, limit: 25 } }),
        },
      );
      if (!response.ok) throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
      const entries = await response.json<Array<{ document?: { fields?: Record<string, unknown>; updateTime?: string } }>>();
      return entries.flatMap(({ document }) => document ? [{ fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)])), updateTime: document.updateTime }] : []);
    },
    async queryJoinRequests(field, value) {
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
        throw new AppError(400, 'invalid_path', 'The request is invalid.');
      }
      const accessToken = await mintAccessToken(serviceAccount(), requestFetch, testOnly?.signedAssertionProvider);
      const response = await requestFetch(
        `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
          body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'institute_join_requests' }], where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } }, limit: 25 } }),
        },
      );
      if (!response.ok) throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
      const entries = await response.json<Array<{ document?: { fields?: Record<string, unknown>; updateTime?: string } }>>();
      return entries.flatMap(({ document }) => document ? [{ fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)])), updateTime: document.updateTime }] : []);
    },
    async queryPendingInstituteAdminRequests() {
      const accessToken = await mintAccessToken(serviceAccount(), requestFetch, testOnly?.signedAssertionProvider);
      const response = await requestFetch(
        `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
          // This bounded, server-only query is reserved for a verified global
          // Super Admin. It is not exposed to clients as an arbitrary query.
          body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'institute_join_requests' }], where: { compositeFilter: { op: 'AND', filters: [
            { fieldFilter: { field: { fieldPath: 'requestedRole' }, op: 'EQUAL', value: { stringValue: 'instituteAdmin' } } },
            { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: 'pending' } } },
          ] } }, limit: 25 } }),
        },
      );
      if (!response.ok) throw new AppError(503, 'backend_unavailable', 'The trusted service is temporarily unavailable.');
      const entries = await response.json<Array<{ document?: { fields?: Record<string, unknown>; updateTime?: string } }>>();
      return entries.flatMap(({ document }) => document ? [{ fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)])), updateTime: document.updateTime }] : []);
    },
    async commit(writes) {
      if (writes.length == 0 || writes.length > 4) throw new AppError(400, 'invalid_payload', 'The request is invalid.');
      for (const write of writes) assertPath(write.path, true);
      const response = await authorizedFetch(':commit', {
        method: 'POST',
        body: JSON.stringify({
          writes: writes.map((write) => ({
            update: {
              name: `projects/${projectId}/databases/(default)/documents/${write.path}`,
              fields: encodeFields(write.fields),
            },
            currentDocument: write.updateTime
              ? { updateTime: write.updateTime }
              : write.createOnly
                ? { exists: false }
                : undefined,
          })),
        }),
      });
      if (!response.ok) throw new AppError(response.status === 409 ? 409 : 503, response.status === 409 ? 'conflict' : 'backend_unavailable', response.status === 409 ? 'The request changed. Try again.' : 'The trusted service is temporarily unavailable.');
    },
  };
}
