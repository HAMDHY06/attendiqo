// REVIEW-ONLY, UNDEPLOYED. Phone normalization never logs the input number.
import { createHash } from 'node:crypto';
import { SafeCallableError } from './callable_core.mjs';

const reject = () => { throw new SafeCallableError('invalid-argument', 'The request contains invalid information.'); };
export const phoneHash = value => createHash('sha256').update(value).digest('hex');
export function normalizeSriLankanMobile(value) {
  if (typeof value !== 'string') reject();
  const compact = value.replace(/[\s()-]/g, '');
  const local = compact.startsWith('0') ? compact.slice(1) : compact;
  const normalized = local.startsWith('+94') ? local : local.startsWith('94') ? `+${local}` : `+94${local}`;
  if (!/^\+947\d{8}$/.test(normalized)) reject();
  return normalized;
}
