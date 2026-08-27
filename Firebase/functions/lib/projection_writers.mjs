// Review-only adapter. Projection logic remains canonical inside this package.
// FieldValue injection ensures one firebase-admin runtime owns every sentinel.
import { FieldValue } from 'firebase-admin/firestore';
import * as canonical from './parent_projection_writers.mjs';

const withFieldValue = (operation) => (values) => operation({ ...values, fieldValue: FieldValue });

export const invalidateStudentLinksForInstituteMove = withFieldValue(canonical.invalidateStudentLinksForInstituteMove);
export const publishParentNotice = withFieldValue(canonical.publishParentNotice);
export const revokeParentLink = withFieldValue(canonical.revokeParentLink);
export const syncAttendanceProjection = withFieldValue(canonical.syncAttendanceProjection);
export const syncClassProjection = withFieldValue(canonical.syncClassProjection);
export const syncInstitutePublicProfile = withFieldValue(canonical.syncInstitutePublicProfile);
export const syncStudentProjection = withFieldValue(canonical.syncStudentProjection);
export const upsertParentLink = withFieldValue(canonical.upsertParentLink);
