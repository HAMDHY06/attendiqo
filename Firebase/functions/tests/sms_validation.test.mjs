import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSriLankanMobile, phoneHash } from '../lib/sms_validation.mjs';
import { MockSmsProvider } from '../lib/sms_provider.mjs';
test('Sri Lankan mobile values normalize safely without returning logs', () => {
  assert.equal(normalizeSriLankanMobile('077 123 4567'), '+94771234567');
  assert.equal(normalizeSriLankanMobile('+94 77 123 4567'), '+94771234567');
  assert.throws(() => normalizeSriLankanMobile('0112345678'));
  assert.notEqual(phoneHash('+94771234567'), '+94771234567');
});
test('mock provider is local-only and provider-neutral', async () => {
  const provider = new MockSmsProvider(); await provider.sendMessage({ to: '+94771234567', body: 'safe' });
  assert.equal((await provider.healthCheck()).provider, 'mock'); assert.equal(provider.sent.length, 1);
});
