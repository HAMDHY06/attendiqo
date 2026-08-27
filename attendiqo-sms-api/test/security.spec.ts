import { describe, expect, it } from 'vitest';
import { AppError, normalizeSriLankanMobile, safeHash } from '../src/security';

describe('SMS privacy validation', () => {
  it('normalizes supported Sri Lankan mobile formats without returning the input', () => {
    expect(normalizeSriLankanMobile('077 123 4567')).toBe('+94771234567');
    expect(normalizeSriLankanMobile('+94 77 123 4567')).toBe('+94771234567');
  });

  it('rejects landlines and malformed phone values with a safe error', () => {
    expect(() => normalizeSriLankanMobile('0112345678')).toThrow(AppError);
    try { normalizeSriLankanMobile('0112345678'); } catch (error) {
      expect(error).toMatchObject({ code: 'recipient_unavailable' });
      expect(String(error)).not.toContain('0112345678');
    }
  });

  it('uses a deterministic one-way hash for de-duplication identifiers', async () => {
    const hash = await safeHash('institute-a:student-a:importantNotice:event-a');
    expect(hash).toHaveLength(64);
    expect(hash).not.toContain('student-a');
    expect(await safeHash('institute-a:student-a:importantNotice:event-a')).toBe(hash);
  });
});
