// Review-only operator entry point. These exports delegate to the canonical
// self-contained Functions writers. The separately tested callable boundary
// adds ID-token verification, App Check, limits, idempotency, and safe errors;
// neither this entry point nor the callable package has been deployed.
export {
  invalidateStudentLinksForInstituteMove,
  publishParentNotice,
  revokeParentLink,
  syncAttendanceProjection,
  syncClassProjection,
  syncInstitutePublicProfile,
  syncStudentProjection,
  upsertParentLink,
} from './lib/parent_projection_writers.mjs';
