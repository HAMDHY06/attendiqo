// Review-only migration primitive for the discovery index on a parent profile.
// `parent_student_links` remains authoritative; clients cannot invoke this.
import { FieldValue } from 'firebase-admin/firestore';
import { deterministicParentLinkId } from './parent_projection_validation.mjs';

const orderedUnique = (values) => [...new Set(values)].sort();
const safeBatchSize = (value) => Number.isInteger(value) && value > 0 && value <= 100 ? value : 50;

const activeConsistentLinks = async ({ firestore, parentUid }) => {
  const snap = await firestore.collection('parent_student_links')
    .where('parentUid', '==', parentUid).where('active', '==', true).limit(100).get();
  const valid = [];
  const rejected = [];
  for (const link of snap.docs) {
    const value = link.data();
    if (link.id !== deterministicParentLinkId(value.parentUid, value.studentId)
      || value.parentUid !== parentUid || typeof value.studentId !== 'string'
      || typeof value.instituteId !== 'string') {
      rejected.push(link.id);
      continue;
    }
    const profile = await firestore.collection('parent_student_profiles').doc(value.studentId).get();
    if (!profile.exists || profile.data()?.studentId !== value.studentId
      || profile.data()?.instituteId !== value.instituteId) {
      rejected.push(link.id);
      continue;
    }
    valid.push(value.studentId);
  }
  return { studentIds: orderedUnique(valid), rejected };
};

/**
 * Processes one bounded ordered link page. It recomputes each encountered
 * parent's *full* index, preventing an incomplete page from dropping links.
 * A protected checkpoint contains only a link cursor, never logged output.
 */
export async function runParentLinkDiscoveryBatch({
  firestore, runId, dryRun = true, batchSize = 50, cursor = null,
  fieldValue = FieldValue,
}) {
  if (typeof runId !== 'string' || runId.length < 8) throw new Error('Migration run ID is invalid.');
  const size = safeBatchSize(batchSize);
  let query = firestore.collection('parent_student_links').orderBy('__name__').limit(size);
  if (cursor) query = query.startAfter(cursor);
  const page = await query.get();
  const parentUids = orderedUnique(page.docs.map((item) => item.data()?.parentUid).filter((item) => typeof item === 'string'));
  let updatedParents = 0;
  let blockedParents = 0;
  for (const parentUid of parentUids) {
    const { studentIds, rejected } = await activeConsistentLinks({ firestore, parentUid });
    if (rejected.length > 0) {
      blockedParents += 1;
      continue;
    }
    const userRef = firestore.collection('users').doc(parentUid);
    const existing = await userRef.get();
    const before = Array.isArray(existing.data()?.parentLinkedStudentIds)
      ? orderedUnique(existing.data().parentLinkedStudentIds.filter((item) => typeof item === 'string')) : [];
    if (JSON.stringify(before) !== JSON.stringify(studentIds)) {
      updatedParents += 1;
      if (!dryRun) {
        await userRef.set({
          parentLinkedStudentIds: studentIds,
          parentLinkedStudentIdsUpdatedAt: fieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
  }
  const nextCursor = page.empty ? null : page.docs.at(-1).id;
  const summary = {
    runId, dryRun, scannedLinks: page.size, parents: parentUids.length,
    updatedParents, blockedParents, complete: page.size < size,
  };
  if (!dryRun) {
    await firestore.collection('parent_link_migration_checkpoints').doc(runId).set({
      ...summary, cursor: nextCursor,
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return { ...summary, nextCursor };
}
