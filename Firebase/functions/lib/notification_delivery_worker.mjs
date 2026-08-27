// REVIEW-ONLY, UNDEPLOYED. It is deliberately not exported as a scheduled Function.
import { createHash } from 'node:crypto';

const hash = value => createHash('sha256').update(value).digest('hex');
export const deliveryIdFor = ({ notificationId, tokenHash }) => hash(`${notificationId}:${tokenHash}`).slice(0, 48);
const failure = error => {
  const code = String(error?.code ?? '');
  if (/registration-token-not-registered|invalid-registration-token/.test(code)) return 'invalid-token';
  if (/unavailable|internal|deadline-exceeded/.test(code)) return 'transient';
  return 'permanent';
};

/**
 * Processes a bounded batch through injected trusted adapters.  Adapters keep
 * FCM tokens inside backend code and make this worker testable without FCM.
 */
export async function processNotificationOutbox({ listPending, claim, listActiveDevices, send, record, updateOutbox, deactivateToken, limit = 25, maxAttempts = 4, dryRun = false, logger = () => {} }) {
  const messages = (await listPending(limit)).slice(0, limit); const metrics = { scanned: messages.length, sent: 0, retry: 0, failed: 0, skipped: 0 };
  for (const item of messages) {
    if (!await claim(item.notificationId)) { metrics.skipped++; continue; }
    const devices = await listActiveDevices(item.recipientUid);
    if (!devices.length) { if (!dryRun) await updateOutbox(item.notificationId, { status: 'skipped' }); metrics.skipped++; continue; }
    let retry = false;
    for (const device of devices) {
      const deliveryId = deliveryIdFor({ notificationId: item.notificationId, tokenHash: device.tokenHash });
      if (dryRun) continue;
      try {
        const result = await send({ token: device.protectedToken, notification: { title: item.title, body: item.body }, data: { route: item.route } });
        await record({ deliveryId, notificationId: item.notificationId, tokenHash: device.tokenHash, status: 'sent', providerMessageIdHash: hash(String(result?.messageId ?? '')), attemptNumber: (item.attempts ?? 0) + 1 }); metrics.sent++;
      } catch (error) {
        const category = failure(error);
        await record({ deliveryId, notificationId: item.notificationId, tokenHash: device.tokenHash, status: category === 'transient' ? 'retry' : 'failed', failureCategory: category, attemptNumber: (item.attempts ?? 0) + 1 });
        if (category === 'invalid-token') await deactivateToken(device.tokenHash);
        retry ||= category === 'transient'; metrics[category === 'transient' ? 'retry' : 'failed']++;
      }
    }
    if (!dryRun) await updateOutbox(item.notificationId, { status: retry && (item.attempts ?? 0) + 1 < maxAttempts ? 'retry' : retry ? 'failed' : 'sent', attempts: (item.attempts ?? 0) + 1 });
  }
  logger({ event: 'notification_delivery_batch', ...metrics }); return metrics;
}
