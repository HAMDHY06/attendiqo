// REVIEW-ONLY, UNDEPLOYED. Mock provider only; not a scheduled Function.
import { createHash } from 'node:crypto';
export const smsDeliveryIdFor = ({ messageId, phoneHash }) => createHash('sha256').update(`${messageId}:${phoneHash}`).digest('hex').slice(0, 48);
export async function processSmsOutbox({ listPending, claim, provider, record, updateOutbox, limit = 20, dryRun = false, logger = () => {} }) {
  const messages = (await listPending(limit)).slice(0, limit); let sent = 0; let failed = 0;
  for (const item of messages) {
    if (!await claim(item.messageId)) continue;
    if (dryRun) continue;
    try { const result = await provider.sendMessage({ to: item.protectedPhone, body: item.body }); await record({ deliveryId: smsDeliveryIdFor({ messageId: item.messageId, phoneHash: item.recipientPhoneHash }), messageId: item.messageId, status: 'sent', providerMessageIdHash: createHash('sha256').update(String(result.providerMessageId ?? '')).digest('hex') }); await updateOutbox(item.messageId, { status: 'sent' }); sent++; }
    catch (error) { await updateOutbox(item.messageId, { status: provider.classifyError(error) === 'transient' ? 'retry' : 'failed' }); failed++; }
  }
  logger({ event: 'sms_delivery_batch', scanned: messages.length, sent, failed }); return { scanned: messages.length, sent, failed };
}
