import test from 'node:test';
import assert from 'node:assert/strict';
import { assertSupportedNodeRuntime } from '../lib/runtime_guard.mjs';

test('production runtime is pinned to Node 22', () => {
  assert.deepEqual(assertSupportedNodeRuntime({ version: '22.18.0', emulator: false }), {
    major: 22, production: true, emulatorFallback: false,
  });
  assert.throws(
    () => assertSupportedNodeRuntime({ version: '24.4.1', emulator: false }),
    /Expected Node 22/,
  );
});

test('Node 24 is accepted only as an explicit local emulator fallback', () => {
  assert.deepEqual(assertSupportedNodeRuntime({ version: '24.4.1', emulator: true }), {
    major: 24, production: false, emulatorFallback: true,
  });
  assert.throws(
    () => assertSupportedNodeRuntime({ version: '20.19.0', emulator: true }),
    /Expected Node 22/,
  );
});
