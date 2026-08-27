import test from 'node:test';
import assert from 'node:assert/strict';
import { tokenIdFor, tokenHash } from '../lib/self_service_callable_core.mjs';
import { validateDeviceRegistration } from '../lib/notification_device_writer.mjs';

const valid = Object.freeze({ token: 'x'.repeat(64), appPackage: 'com.hamdhytech.attendiqo.connect', platform: 'android', appVersion: '1.0.0', deviceHash: 'd'.repeat(32), permissionStatus: 'granted' });
test('notification device IDs are deterministic and token hashes are not raw tokens', () => {
  assert.equal(tokenIdFor(valid), tokenIdFor(valid));
  assert.notEqual(tokenHash(valid.token), valid.token);
});
test('notification registration rejects unknown, unsupported and malformed fields', () => {
  assert.deepEqual(validateDeviceRegistration({...valid}), valid);
  assert.throws(() => validateDeviceRegistration({...valid, uid: 'other'}));
  assert.throws(() => validateDeviceRegistration({...valid, platform: 'ios'}));
  assert.throws(() => validateDeviceRegistration({...valid, token: 'short'}));
});
