import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index';

type Settings = { enabled: boolean; monthlyLimit: number; allowedEvents: string[]; templates: Record<string, string> };
type EntryStatus = 'reserved' | 'sent' | 'retry' | 'failed';

/**
 * Spark-compatible per-institute quota and de-duplication ledger.  Durable
 * Object storage is the only mutable backend state used by the Worker; it is
 * never exposed to a Flutter client and contains no phone number or SMS body.
 */
export class SmsLedger extends DurableObject {
  constructor(ctx: DurableObjectState, env: Env) { super(ctx, env); }
  private readonly defaultSettings: Settings = { enabled: false, monthlyLimit: 500, allowedEvents: [], templates: {} };
  async fetch(request: Request): Promise<Response> {
    const data = await request.json<Record<string, unknown>>(); const path = new URL(request.url).pathname;
    const current = await this.ctx.storage.get<Settings>('settings') ?? this.defaultSettings;
    if (path === '/settings') return this.response({ ...current });
    if (path === '/settings-update') {
      const next: Settings = { enabled: data.enabled as boolean, monthlyLimit: data.monthlyLimit as number, allowedEvents: data.allowedEvents as string[], templates: data.templates as Record<string, string> };
      await this.ctx.storage.put('settings', next);
      return this.response({ enabled: next.enabled, monthlyLimit: next.monthlyLimit, allowedEvents: next.allowedEvents });
    }
    const usage = await this.ctx.storage.get<{ used: number; reserved: number }>('usage') ?? { used: 0, reserved: 0 };
    if (path === '/usage') return this.response({ enabled: current.enabled, monthlyLimit: current.monthlyLimit, used: usage.used, reserved: usage.reserved, remaining: Math.max(0, current.monthlyLimit - usage.used - usage.reserved) });
    const notificationId = data.notificationId as string;
    if (path === '/reserve') {
      const prior = await this.ctx.storage.get<EntryStatus>(`entry:${notificationId}`);
      if (prior) return this.response({ status: 'duplicate' });
      if (usage.used + usage.reserved >= current.monthlyLimit) return this.response({ status: 'quota_exceeded' });
      await this.ctx.storage.put(`entry:${notificationId}`, 'reserved');
      await this.ctx.storage.put('usage', { ...usage, reserved: usage.reserved + 1 });
      return this.response({ status: 'reserved' });
    }
    if (path === '/complete') {
      if (await this.ctx.storage.get<EntryStatus>(`entry:${notificationId}`) !== 'reserved') return this.response({ status: 'duplicate' });
      const status: EntryStatus = data.status === 'sent' ? 'sent' : data.status === 'retry' ? 'retry' : 'failed';
      await this.ctx.storage.put(`entry:${notificationId}`, status);
      await this.ctx.storage.put('usage', { used: usage.used + (status === 'sent' ? 1 : 0), reserved: Math.max(0, usage.reserved - 1) });
      return this.response({ status });
    }
    return this.response({ error: 'not_found' }, 404);
  }
  private response(value: unknown, status = 200) { return new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } }); }
}
