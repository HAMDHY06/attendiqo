// REVIEW-ONLY operator utility. Requires external Admin credentials; it never
// runs from mobile clients and does not print parent or student identifiers.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { runParentLinkDiscoveryBatch } from '../lib/parent_link_discovery_migration.mjs';

const args = new Map(process.argv.slice(2).map((value) => {
  const [key, raw = 'true'] = value.split('='); return [key, raw];
}));
const mode = args.has('--execute') ? 'execute' : 'dry-run';
const runId = args.get('--run-id') ?? `parent-link-${Date.now()}`;
const batchSize = Number(args.get('--batch-size') ?? 50);
const cursor = args.get('--cursor') ?? null;
if (!args.has('--dry-run') && !args.has('--execute')) {
  throw new Error('Specify --dry-run or --execute.');
}
initializeApp({ credential: applicationDefault() });
const result = await runParentLinkDiscoveryBatch({
  firestore: getFirestore(), runId, dryRun: mode === 'dry-run', batchSize, cursor,
});
// Deliberately aggregate-only output: no email, name, phone, UID, or student ID.
console.log(JSON.stringify({ mode, ...result, nextCursorStored: mode === 'execute' && !result.complete }));
