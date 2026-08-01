export const TEACHER_PERMISSIONS = Object.freeze([
  'canCreateClasses',
  'canEditClasses',
  'canAddStudents',
  'canEditStudents',
  'canGenerateQrCodes',
  'canTakeAttendance',
  'canCorrectAttendance',
  'canExportReports',
  'canViewParentContacts',
  'canSendManualNotifications',
]);

export function hasExactTeacherPermissions(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const keys = Object.keys(value).sort();
  const expected = [...TEACHER_PERMISSIONS].sort();
  return keys.length === expected.length
    && keys.every((key, index) => key === expected[index])
    && Object.values(value).every((entry) => typeof entry === 'boolean');
}

export function authorizeInstituteActor({ actor, institute, targetInstituteId }) {
  if (!actor?.active || !institute?.active || institute.status !== 'active') return false;
  if (actor.role === 'superAdmin') return actor.verifiedSuperAdminClaim === true;
  return actor.role === 'instituteAdmin'
    && actor.instituteId === targetInstituteId
    && institute.instituteId === targetInstituteId;
}

export function authorizeTeacherClassAction({
  actor,
  institute,
  academicClass,
  permission,
  creating = false,
  backendAvailable = true,
}) {
  if (!backendAvailable || !TEACHER_PERMISSIONS.includes(permission)) return false;
  if (!actor?.active || !institute?.active || institute.status !== 'active') return false;
  if (actor.role !== 'teacher' || !hasExactTeacherPermissions(actor.permissions)) return false;
  if (actor.instituteId !== institute.instituteId) return false;
  if (actor.permissions[permission] !== true) return false;
  if (creating) return permission === 'canCreateClasses';
  return academicClass?.instituteId === actor.instituteId
    && academicClass.status !== 'archived'
    && academicClass.teacherIds?.includes(actor.uid) === true;
}
