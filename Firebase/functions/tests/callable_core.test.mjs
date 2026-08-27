import test from 'node:test';
import assert from 'node:assert/strict';
import { mapCallableError, SafeCallableError } from '../lib/callable_core.mjs';

test('safe callable errors are preserved', () => {
  const input = new SafeCallableError('permission-denied', 'Safe message.');
  assert.equal(mapCallableError(input), input);
});

test('internal errors never expose raw exception details', () => {
  const mapped = mapCallableError(new Error('Firebase path /students/private-secret exploded'));
  assert.equal(mapped.code, 'internal');
  assert.equal(mapped.message, 'The operation could not be completed safely.');
  assert.equal(mapped.message.includes('private-secret'), false);
});

test('known validation and authorization failures map to stable safe codes', () => {
  assert.equal(mapCallableError(new Error('Student is not active.')).code, 'permission-denied');
  assert.equal(mapCallableError(new Error('sourceVersion must be valid.')).code, 'invalid-argument');
  assert.equal(mapCallableError(new Error('Stale sourceVersion rejected.')).code, 'failed-precondition');
});
