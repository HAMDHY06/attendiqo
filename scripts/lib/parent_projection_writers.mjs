// Compatibility surface for operator scripts. The sole business implementation
// is packaged with Functions; injection keeps Firestore sentinels on this
// script package's firebase-admin runtime.
import { FieldValue } from 'firebase-admin/firestore';
import * as canonical from '../../Firebase/functions/lib/parent_projection_writers.mjs';

const withFieldValue = (operation) => (values) => operation({
  ...values,
  fieldValue: FieldValue,
});

export const invalidateStudentLinksForInstituteMove = withFieldValue(canonical.invalidateStudentLinksForInstituteMove);
export const publishParentNotice = withFieldValue(canonical.publishParentNotice);
export const revokeParentLink = withFieldValue(canonical.revokeParentLink);
export const syncAttendanceProjection = withFieldValue(canonical.syncAttendanceProjection);
export const syncClassProjection = withFieldValue(canonical.syncClassProjection);
export const syncInstitutePublicProfile = withFieldValue(canonical.syncInstitutePublicProfile);
export const syncStudentProjection = withFieldValue(canonical.syncStudentProjection);
export const upsertParentLink = withFieldValue(canonical.upsertParentLink);
