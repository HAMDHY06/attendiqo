import test from 'node:test'; import assert from 'node:assert/strict';
import { writeSmsOutbox } from '../lib/sms_outbox_writer.mjs';
const values = new Map(); const firestore = { collection: name => ({ doc: id => ({ id, get: async () => name === 'users' ? ({ exists: true, data: () => ({ active: true, instituteId: 'inst' }) }) : ({ exists: values.has(id) }) }) }), runTransaction: fn => fn({ get: r => r.get(), create: (r,v) => values.set(r.id,v) }) };
const data = { recipientUid:'parent', phone:'0771234567', instituteId:'inst', eventType:'urgentInstituteNotice', sourceVersion:1, deduplicationKey:'event' };
test('SMS outbox is idempotent and stores only protected trusted phone', async () => { await writeSmsOutbox({ firestore,...data }); await writeSmsOutbox({ firestore,...data }); assert.equal(values.size,1); assert.notEqual([...values.values()][0].recipientPhoneHash,'+94771234567'); });
test('SMS outbox rejects sensitive template data', async () => { await assert.rejects(writeSmsOutbox({ firestore,...data,safeTemplateData:{phone:'x'} })); });
