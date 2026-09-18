import { AppError, type Fetcher } from './security';
import { mintAccessToken, parseAccount, type ServiceAccount } from './worker-firestore-admin';

const projectId = 'attendiqo-system';
const cloudScope = 'https://www.googleapis.com/auth/cloud-platform';

type IdentityUser = { localId?: string };

export type WorkerIdentityAdmin = {
  createUser(input: { uid: string; email: string; password: string; displayName: string }): Promise<string>;
  setClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
  setDisabled(uid: string, disabled: boolean): Promise<void>;
  deleteUser(uid: string): Promise<void>;
};

export function createWorkerIdentityAdmin(
  serviceAccountJson: string,
  apiKey: string,
  requestFetch: Fetcher = fetch,
): WorkerIdentityAdmin {
  let account: ServiceAccount | undefined;
  const serviceAccount = () => account ??= parseAccount(serviceAccountJson);
  const call = async (path: string, payload: Record<string, unknown>): Promise<IdentityUser> => {
    if (!apiKey || apiKey.length < 20) throw new AppError(503, 'backend_unavailable', 'The trusted account service is unavailable.');
    const token = await mintAccessToken(serviceAccount(), requestFetch, undefined, cloudScope);
    const separator = path.includes('?') ? '&' : '?';
    const response = await requestFetch(`https://identitytoolkit.googleapis.com/v1/${path}${separator}key=${encodeURIComponent(apiKey)}`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const body = await response.json<{ localId?: string; error?: { message?: string } }>().catch(() => ({} as { localId?: string; error?: { message?: string } }));
    if (!response.ok) {
      const code = body.error?.message ?? '';
      if (code.includes('EMAIL_EXISTS')) throw new AppError(409, 'duplicate_email', 'An account already uses this email address.');
      if (code.includes('LOCAL_ID_EXISTS')) throw new AppError(409, 'account_conflict', 'The account could not be created. Please try again.');
      throw new AppError(503, 'account_backend_unavailable', 'The trusted account service is temporarily unavailable.');
    }
    return body;
  };
  return {
    async createUser(input) {
      const result = await call(`projects/${projectId}/accounts`, {
        localId: input.uid,
        email: input.email,
        password: input.password,
        displayName: input.displayName,
        emailVerified: false,
        disabled: false,
      });
      if (result.localId !== input.uid) throw new AppError(503, 'account_backend_unavailable', 'The trusted account service is temporarily unavailable.');
      return input.uid;
    },
    async setClaims(uid, claims) {
      await call('accounts:update', { localId: uid, targetProjectId: projectId, customAttributes: JSON.stringify(claims) });
    },
    async setDisabled(uid, disabled) {
      await call('accounts:update', { localId: uid, targetProjectId: projectId, disableUser: disabled });
    },
    async deleteUser(uid) {
      await call(`projects/${projectId}/accounts:delete`, { localId: uid });
    },
  };
}
