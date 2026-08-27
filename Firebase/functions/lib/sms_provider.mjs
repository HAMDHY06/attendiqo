// REVIEW-ONLY mock-only provider interface. Never add provider credentials here.
export class MockSmsProvider {
  constructor({ result = { providerMessageId: 'mock-message' } } = {}) { this.result = result; this.sent = []; }
  async sendMessage({ to, body }) { this.sent.push({ to, body }); return this.result; }
  classifyError(error) { return String(error?.code ?? '').includes('temporary') ? 'transient' : 'permanent'; }
  normalizeProviderResponse(value) { return { providerMessageId: String(value?.providerMessageId ?? '') }; }
  validateConfiguration() { return true; }
  async healthCheck() { return { healthy: true, provider: 'mock' }; }
}
