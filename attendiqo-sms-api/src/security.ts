export class AppError extends Error {
  constructor(public status: number, public code: string, public safeMessage: string) { super(safeMessage); }
}

export type FirestoreDocument = { fields: Record<string, unknown>; updateTime?: string };
export type AuthenticatedUser = { uid: string; role: string; active: boolean; instituteId?: string; superAdmin: boolean };

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4);
  const raw = atob(padded); return Uint8Array.from(raw, c => c.charCodeAt(0));
}
function decodeJson(value: string): Record<string, unknown> { try { return JSON.parse(new TextDecoder().decode(base64UrlDecode(value))) as Record<string, unknown>; } catch { throw new AppError(401, 'invalid_token', 'Authentication could not be verified.'); } }

export type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

/** Verifies Firebase tokens against Google's published Secure Token JWKS. */
export async function verifyFirebaseToken(token: string, projectId: string, requestFetch: Fetcher = fetch): Promise<{ uid: string; superAdmin: boolean }> {
  const parts = token.split('.'); if (parts.length !== 3) throw new AppError(401, 'invalid_token', 'Authentication could not be verified.');
  const header = decodeJson(parts[0]); const claims = decodeJson(parts[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' || claims.aud !== projectId || claims.iss !== `https://securetoken.google.com/${projectId}` || typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128) throw new AppError(401, 'invalid_token', 'Authentication could not be verified.');
  const now = Math.floor(Date.now() / 1000); if (typeof claims.exp !== 'number' || typeof claims.iat !== 'number' || claims.exp <= now || claims.iat > now + 300) throw new AppError(401, 'expired_token', 'Authentication has expired.');
  const jwks = await requestFetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com').then(r => r.ok ? r.json<{ keys?: Record<string, unknown>[] }>() : Promise.reject(new Error('jwks'))).catch(() => { throw new AppError(503, 'identity_unavailable', 'Authentication verification is unavailable.'); });
  const jwk = jwks.keys?.find(value => value.kid === header.kid && value.kty === 'RSA' && value.alg === 'RS256');
  if (!jwk) throw new AppError(401, 'invalid_token', 'Authentication could not be verified.');
  const key = await crypto.subtle.importKey('jwk', jwk as unknown as JsonWebKey, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']).catch(() => { throw new AppError(503, 'identity_unavailable', 'Authentication verification is unavailable.'); });
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, base64UrlDecode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!valid) throw new AppError(401, 'invalid_token', 'Authentication could not be verified.'); return { uid: claims.sub, superAdmin: claims.superAdmin === true };
}

function firestoreValue(value: unknown): unknown {
  if (!value || typeof value !== 'object') return undefined; const v = value as Record<string, unknown>;
  if ('stringValue' in v) return v.stringValue; if ('booleanValue' in v) return v.booleanValue; if ('integerValue' in v) return Number(v.integerValue); if ('doubleValue' in v) return v.doubleValue;
  if ('arrayValue' in v) return ((v.arrayValue as { values?: unknown[] }).values ?? []).map(firestoreValue);
  if ('mapValue' in v) return Object.fromEntries(Object.entries((v.mapValue as { fields?: Record<string, unknown> }).fields ?? {}).map(([k, x]) => [k, firestoreValue(x)])); return undefined;
}
export async function fetchDocument(request: Request, path: string): Promise<FirestoreDocument | undefined> {
  if (!/^[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(path)) throw new AppError(400, 'invalid_path', 'The request is invalid.');
  const auth = request.headers.get('authorization'); const response = await fetch(`https://firestore.googleapis.com/v1/projects/attendiqo-system/databases/(default)/documents/${path}`, { headers: { authorization: auth ?? '' } });
  if (response.status === 404) return undefined; if (!response.ok) throw new AppError(response.status === 403 ? 403 : 503, response.status === 403 ? 'permission_denied' : 'data_unavailable', response.status === 403 ? 'You are not permitted to use SMS for this record.' : 'SMS data is temporarily unavailable.');
  const document = await response.json<{ fields?: Record<string, unknown> }>(); return { fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([k, v]) => [k, firestoreValue(v)])) };
}
export async function authenticate(
  request: Request,
  projectId: string,
  documentLoader: (path: string) => Promise<FirestoreDocument | undefined> =
      (path) => fetchDocument(request, path),
  requestFetch: Fetcher = fetch,
): Promise<AuthenticatedUser> {
  const header = request.headers.get('authorization'); if (!header?.startsWith('Bearer ')) throw new AppError(401, 'unauthenticated', 'Sign in to use SMS.');
  const { uid, superAdmin } = await verifyFirebaseToken(header.slice(7), projectId, requestFetch);
  const profile = await documentLoader(`users/${uid}`); if (!profile) throw new AppError(403, 'profile_missing', 'This account is unavailable.');
  const role = profile.fields.role; const active = profile.fields.active; const instituteId = profile.fields.instituteId;
  if (typeof role !== 'string' || typeof active !== 'boolean' || (instituteId !== undefined && typeof instituteId !== 'string')) throw new AppError(403, 'profile_invalid', 'This account is unavailable.');
  return { uid, role, active, instituteId: instituteId as string | undefined, superAdmin };
}
export function normalizeSriLankanMobile(value: unknown): string {
  if (typeof value !== 'string') throw new AppError(409, 'recipient_unavailable', 'A valid SMS recipient is unavailable.');
  const digits = value.replace(/[\s().-]/g, ''); const local = digits.replace(/^\+94/, '0').replace(/^0094/, '0');
  if (!/^07\d{8}$/.test(local)) throw new AppError(409, 'recipient_unavailable', 'A valid SMS recipient is unavailable.'); return `+94${local.slice(1)}`;
}
export async function safeHash(value: string): Promise<string> { const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)); return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2, '0')).join(''); }
