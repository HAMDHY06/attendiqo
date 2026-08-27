import { describe, expect, it } from 'vitest';
import { handle, type Env } from '../src/index';
import { AppError, verifyFirebaseToken } from '../src/security';

const encoder = new TextEncoder();
const b64 = (value: Uint8Array | string) => {
  const bytes = typeof value === 'string' ? encoder.encode(value) : value;
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
};

async function signedToken(uid = 'admin-a') {
  const keys = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const header = b64(JSON.stringify({ alg: 'RS256', kid: 'test-key' }));
  const now = Math.floor(Date.now() / 1000);
  const claims = b64(JSON.stringify({ aud: 'attendiqo-system', iss: 'https://securetoken.google.com/attendiqo-system', sub: uid, iat: now - 1, exp: now + 300 }));
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keys.privateKey, encoder.encode(`${header}.${claims}`)));
  const privateDer = new Uint8Array(await crypto.subtle.exportKey('pkcs8', keys.privateKey));
  const privatePem = btoa(String.fromCharCode(...privateDer)).replace(/(.{64})/g, '$1\n');
  const privateKey = `-----BEGIN PRIVATE KEY-----\n${privatePem}\n-----END PRIVATE KEY-----`;
  return { token: `${header}.${claims}.${b64(signature)}`, jwk: { ...(await crypto.subtle.exportKey('jwk', keys.publicKey)), kid: 'test-key', alg: 'RS256' }, serviceAccount: JSON.stringify({ project_id: 'attendiqo-system', client_email: 'test@attendiqo-system.iam.gserviceaccount.com', private_key: privateKey }) };
}

const fields = (value: Record<string, unknown>) => ({ fields: Object.fromEntries(Object.entries(value).map(([key, field]) => [key, typeof field === 'boolean' ? { booleanValue: field } : typeof field === 'number' ? { integerValue: String(field) } : { stringValue: String(field) }])) });

function fakeLedger(limit = 1) {
  let used = 0; let reserved = 0; const entries = new Set<string>();
  const config = { enabled: true, monthlyLimit: limit, allowedEvents: ['importantNotice'], templates: {} };
  const stub = {
    fetch: async (_url: string, init?: RequestInit) => {
      const path = new URL(_url).pathname; const data = JSON.parse(String(init?.body ?? '{}')) as Record<string, string>;
      if (path === '/settings') return Response.json(config);
      if (path === '/settings-update') return Response.json(config);
      if (path === '/usage') return Response.json({ used, reserved, remaining: limit - used - reserved });
      if (path === '/reserve') { if (entries.has(data.notificationId)) return Response.json({ status: 'duplicate' }); if (used + reserved >= limit) return Response.json({ status: 'quota_exceeded' }); entries.add(data.notificationId); reserved++; return Response.json({ status: 'reserved' }); }
      if (path === '/complete') { reserved--; if (data.status === 'sent') used++; return Response.json({ status: data.status }); }
      return new Response(null, { status: 404 });
    },
  };
  return { namespace: { getByName: () => stub } as unknown as DurableObjectNamespace, stub };
}

function mockOutbound(
  fixture: Awaited<ReturnType<typeof signedToken>>,
  instituteId: string,
  providerStatus = 200,
): { providerCalls: () => number } {
  let providerCalls = 0;
  const transport = async (input: RequestInfo | URL): Promise<Response> => {
    const url = input instanceof Request ? input.url : String(input);
    if (url.includes('/jwk/securetoken')) return Response.json({ keys: [fixture.jwk] });
    if (url === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'test-access-token-with-safe-length' });
    if (url.endsWith('/users/admin-a')) return Response.json(fields({ role: 'instituteAdmin', active: true, instituteId }));
    if (url.endsWith(`/institutes/${instituteId}`)) return Response.json(fields({ active: true, status: 'active', name: 'Institute' }));
    if (url.endsWith('/students/student-a')) return Response.json(fields({ active: true, instituteId, fullName: 'Student', primaryParentMobile: '0771234567' }));
    if (url.endsWith('/student_sms_consents/student-a')) return Response.json(fields({ granted: true, instituteId }));
    if (url.includes('text.lk')) { providerCalls++; return new Response('{}', { status: providerStatus }); }
    return new Response(null, { status: 404 });
  };
  return { providerCalls: () => providerCalls, transport };
}

describe('signed Firebase identity fixture', () => {
  it('cryptographically accepts a valid project-scoped signed token', async () => {
    const fixture = await signedToken();
    await expect(verifyFirebaseToken(fixture.token, 'attendiqo-system', async () => Response.json({ keys: [fixture.jwk] }))).resolves.toEqual({ uid: 'admin-a', superAdmin: false });
  });

  it('rejects invalid signatures without returning token material', async () => {
    const fixture = await signedToken();
    const parts = fixture.token.split('.');
    const signature = parts[2];
    const forged = `${parts[0]}.${parts[1]}.${signature[0] === 'A' ? 'B' : 'A'}${signature.slice(1)}`;
    await expect(verifyFirebaseToken(forged, 'attendiqo-system', async () => Response.json({ keys: [fixture.jwk] }))).rejects.toMatchObject({ code: 'invalid_token' } satisfies Partial<AppError>);
  });
});

describe('Worker SMS integration with mocked Text.lk', () => {
  it('rejects a credential-free request before parsing the backend-only service credential', async () => {
    const response = await handle(
      new Request('https://worker.example/v1/memberships/list', { method: 'POST', body: '{}' }),
      {
        SMS_LEDGER: fakeLedger().namespace,
        TEXTLK_API_TOKEN: 'test-secret',
        TEXTLK_SENDER_ID: 'HamdhyTech',
        FIREBASE_SERVICE_ACCOUNT_JSON: 'not-parsed-for-anonymous-requests',
      } as unknown as Env,
    );
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'unauthenticated', message: 'Sign in to use SMS.' });
  });

  it('rejects an invalid bearer before using the backend-only service credential', async () => {
    await expect(handle(
      new Request('https://worker.example/v1/memberships/list', {
        method: 'POST',
        headers: { authorization: 'Bearer invalid-test-token' },
        body: '{}',
      }),
      {
        SMS_LEDGER: fakeLedger().namespace,
        TEXTLK_API_TOKEN: 'test-secret',
        TEXTLK_SENDER_ID: 'HamdhyTech',
        FIREBASE_SERVICE_ACCOUNT_JSON: 'not-parsed-for-invalid-tokens',
      } as unknown as Env,
    )).rejects.toMatchObject({ code: 'invalid_token' } satisfies Partial<AppError>);
  });

  it('authorizes an active same-institute admin, sends once, settles quota, and suppresses a duplicate', async () => {
    const fixture = await signedToken();
    const mocked = mockOutbound(fixture, 'institute-a');
    const ledger = fakeLedger();
    const workerEnv = { SMS_LEDGER: ledger.namespace, TEXTLK_API_TOKEN: 'test-secret', TEXTLK_SENDER_ID: 'HamdhyTech', FIREBASE_SERVICE_ACCOUNT_JSON: fixture.serviceAccount } as unknown as Env;
    const call = () => handle(new Request('https://worker.example/v1/send', { method: 'POST', headers: { authorization: `Bearer ${fixture.token}`, 'content-type': 'application/json' }, body: JSON.stringify({ studentId: 'student-a', eventType: 'importantNotice', sourceEventKey: 'event-1' }) }), workerEnv, mocked.transport, { signedAssertionProvider: async () => 'test-assertion' });
    expect(await (await call()).json()).toEqual({ status: 'sent' });
    expect(await (await call()).json()).toEqual({ status: 'duplicate' });
    expect(mocked.providerCalls()).toBe(1);
    expect(await (await ledger.stub.fetch('https://ledger/usage', { method: 'POST', body: '{}' })).json()).toMatchObject({ used: 1, reserved: 0, remaining: 0 });
  });

  it('releases a quota reservation for a retryable provider failure', async () => {
    const fixture = await signedToken();
    const mocked = mockOutbound(fixture, 'institute-retry', 503);
    const ledger = fakeLedger();
    const workerEnv = { SMS_LEDGER: ledger.namespace, TEXTLK_API_TOKEN: 'test-secret', TEXTLK_SENDER_ID: 'HamdhyTech', FIREBASE_SERVICE_ACCOUNT_JSON: fixture.serviceAccount } as unknown as Env;
    const response = await handle(new Request('https://worker.example/v1/send', { method: 'POST', headers: { authorization: `Bearer ${fixture.token}`, 'content-type': 'application/json' }, body: JSON.stringify({ studentId: 'student-a', eventType: 'importantNotice', sourceEventKey: 'retry-1' }) }), workerEnv, mocked.transport, { signedAssertionProvider: async () => 'test-assertion' });
    expect(response.status).toBe(503);
    expect(await (await ledger.stub.fetch('https://ledger/usage', { method: 'POST', body: '{}' })).json()).toMatchObject({ used: 0, reserved: 0, remaining: 1 });
  });
});

describe('Worker institute membership approval boundary', () => {
  it('creates a pending request and only a same-institute active admin may approve a teacher', async () => {
    const fixture = await signedToken();
    const docs = new Map<string, Record<string, unknown>>([
      ['users/admin-a', { role: 'instituteAdmin', active: true }],
      ['institute_join_codes/ABCDEF', { instituteId: 'institute-a', active: true }],
      ['institutes/institute-a', { active: true, status: 'active' }],
    ]);
    const transport = async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      if (url.includes('/jwk/securetoken')) return Response.json({ keys: [fixture.jwk] });
      if (url === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'test-access-token-with-safe-length' });
      if (url.endsWith(':runQuery')) {
        const body = JSON.parse(String(init?.body ?? '{}')) as { structuredQuery?: { from?: Array<{ collectionId?: string }>; where?: { fieldFilter?: { field?: { fieldPath?: string }; value?: { stringValue?: string } } } } };
        const collection = body.structuredQuery?.from?.[0]?.collectionId;
        const field = body.structuredQuery?.where?.fieldFilter?.field?.fieldPath;
        const value = body.structuredQuery?.where?.fieldFilter?.value?.stringValue;
        const found = [...docs.entries()].filter(([path, fields]) => path.startsWith(`${collection}/`) && fields[field ?? ''] === value)
          .map(([path, values]) => ({ document: { name: path, fields: fields(values), updateTime: 'time-1' } }));
        return Response.json(found);
      }
      if (url.includes(':commit')) {
        const body = JSON.parse(String(init?.body ?? '{}')) as { writes?: Array<{ update?: { name?: string; fields?: Record<string, unknown> } }> };
        for (const write of body.writes ?? []) {
          const name = write.update?.name?.split('/documents/')[1];
          if (!name) continue;
          const converted: Record<string, unknown> = {};
          for (const [key, value] of Object.entries(write.update?.fields ?? {})) {
            const item = value as Record<string, unknown>;
            converted[key] = item.stringValue ?? item.booleanValue ?? item.integerValue;
          }
          docs.set(name, converted);
        }
        return Response.json({});
      }
      const path = url.split('/documents/')[1];
      const value = path ? docs.get(path) : undefined;
      return value ? Response.json(fields(value)) : new Response(null, { status: 404 });
    };
    const environment = { SMS_LEDGER: fakeLedger().namespace, TEXTLK_API_TOKEN: 'test-secret', TEXTLK_SENDER_ID: 'HamdhyTech', FIREBASE_SERVICE_ACCOUNT_JSON: fixture.serviceAccount } as unknown as Env;
    const invoke = (path: string, body: Record<string, unknown>) => handle(new Request(`https://worker.example${path}`, { method: 'POST', headers: { authorization: `Bearer ${fixture.token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) }), environment, transport, { signedAssertionProvider: async () => 'test-assertion' });
    expect(await (await invoke('/v1/memberships/request', { joinCode: 'ABCDEF', requestedRole: 'teacher' })).json()).toEqual({ status: 'pending' });
    const requestId = 'admin-a_institute-a_teacher';
    await expect(invoke('/v1/memberships/review', { requestId, decision: 'approve' }))
      .rejects.toMatchObject({ code: 'forbidden' } satisfies Partial<AppError>);
  });
});
