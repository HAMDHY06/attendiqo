// REVIEW-ONLY bounded reconciliation. It is deliberately explicit and does
// not run a full database scan or write audits for idempotent matches.
export async function reconcileProjectionBatch({ firestore, writers, dryRun = true, batchSize = 25, cursor = null }) {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) throw new Error('Invalid reconciliation batch size.');
  let query = firestore.collection('students').orderBy('__name__').limit(batchSize);
  if (cursor) query = query.startAfter(cursor);
  const page = await query.get();
  const summary = { scanned: page.size, matched: 0, repaired: 0, skipped: 0, blocked: 0, failed: 0, remaining: page.size === batchSize };
  for (const student of page.docs) {
    try {
      const projection = await firestore.collection('parent_student_profiles').doc(student.id).get();
      if (projection.exists && projection.data()?.sourceVersion === student.data()?.sourceVersion) { summary.matched += 1; continue; }
      if (dryRun) { summary.repaired += 1; continue; }
      await writers.syncStudentProjection({ firestore, actorUid: 'trusted-projection-reconciliation', studentId: student.id, trustedSystem: true });
      summary.repaired += 1;
    } catch { summary.blocked += 1; }
  }
  return { ...summary, nextCursor: page.empty ? null : page.docs.at(-1).id };
}
