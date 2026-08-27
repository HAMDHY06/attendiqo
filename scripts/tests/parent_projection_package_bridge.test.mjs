import test from 'node:test';
import assert from 'node:assert/strict';
import * as reference from '../parent_projection_backend_reference.mjs';

test('review utilities expose the canonical packaged writer operations', () => {
  assert.deepEqual(Object.keys(reference).sort(), [
    'invalidateStudentLinksForInstituteMove',
    'publishParentNotice',
    'revokeParentLink',
    'syncAttendanceProjection',
    'syncClassProjection',
    'syncInstitutePublicProfile',
    'syncStudentProjection',
    'upsertParentLink',
  ]);
});
