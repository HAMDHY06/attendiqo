const requiredText = (value, label, max = 160) => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  if (!normalized || normalized.length > max) throw new Error(`${label} is invalid.`);
  return normalized;
};

const optionalText = (value, label, max = 500) => {
  if (value == null || value === '') return null;
  const normalized = requiredText(value, label, max);
  return normalized;
};

export const normalizeSourceVersion = (value) => {
  if (Number.isSafeInteger(value) && value >= 0) return value;
  throw new Error('sourceVersion must be a non-negative integer.');
};

export const assertNewerVersion = (existing, incoming) => {
  const next = normalizeSourceVersion(incoming);
  if (existing == null) return next;
  const current = normalizeSourceVersion(existing);
  if (next < current) throw new Error('Stale sourceVersion rejected.');
  return next;
};

export const deterministicParentLinkId = (parentUid, studentId) =>
  `${requiredText(parentUid, 'parentUid', 128)}_${requiredText(studentId, 'studentId', 128)}`;

export const deterministicAttendanceSummaryId = (studentId, attendanceDateKey, classId) => {
  const date = requiredText(attendanceDateKey, 'attendanceDateKey', 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('attendanceDateKey is invalid.');
  return `${requiredText(studentId, 'studentId', 128)}_${date}_${requiredText(classId, 'classId', 128)}`;
};

export const sanitizeRelationship = (value) => requiredText(value || 'parent', 'relationship', 40);

export const validateLinkSources = ({ actor, parent, student, institute }) => {
  if (actor?.active !== true || actor?.role !== 'instituteAdmin') {
    throw new Error('Actor is not an active Institute Admin.');
  }
  if (!student?.instituteId || actor.instituteId !== student.instituteId) {
    throw new Error('Actor and student institute do not match.');
  }
  if (institute?.active !== true || institute?.status !== 'active'
      || institute?.instituteId !== student.instituteId) {
    throw new Error('Institute is not active or does not match.');
  }
  if (parent?.active !== true || parent?.role !== 'parent') {
    throw new Error('Parent account is not active.');
  }
  if (student?.active !== true) throw new Error('Student is not active.');
};

export const validateExistingLink = ({ existing, instituteId, reactivate = false }) => {
  if (!existing) return 'parentLinkCreated';
  if (existing.instituteId !== instituteId) throw new Error('Cross-institute link rejected.');
  if (existing.active === false) {
    if (!reactivate) throw new Error('Explicit reactivation is required.');
    return 'parentLinkReactivated';
  }
  return null;
};

export const studentProjection = ({ student, classIds = [], sourceVersion }) => ({
  studentId: requiredText(student?.studentId, 'studentId', 128),
  instituteId: requiredText(student?.instituteId, 'instituteId', 128),
  fullName: requiredText(student?.fullName, 'fullName', 160),
  studentNumber: requiredText(student?.studentNumber, 'studentNumber', 64),
  grade: optionalText(student?.grade, 'grade', 64),
  active: student?.active === true,
  classIds: [...new Set(classIds.map((value) => requiredText(value, 'classId', 128)))].sort(),
  publicProfileImageUrl: null,
  sourceVersion: normalizeSourceVersion(sourceVersion),
});

const schedule = (value) => {
  if (value == null) return null;
  const startTime = requiredText(value.startTime, 'startTime', 5);
  const endTime = requiredText(value.endTime, 'endTime', 5);
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(startTime)
      || !/^([01]\d|2[0-3]):[0-5]\d$/.test(endTime)
      || endTime <= startTime) {
    throw new Error('Schedule time is invalid.');
  }
  return {
    daysOfWeek: Array.isArray(value.daysOfWeek)
      ? value.daysOfWeek.map((item) => requiredText(item, 'schedule day', 16))
      : [],
    startTime,
    endTime,
    room: optionalText(value.room, 'room', 120),
    effectiveDate: value.effectiveDate ?? null,
  };
};

export const classProjection = ({ academicClass, teacherDisplayName, effectiveSchedule, sourceVersion }) => ({
  classId: requiredText(academicClass?.classId, 'classId', 128),
  instituteId: requiredText(academicClass?.instituteId, 'instituteId', 128),
  className: requiredText(academicClass?.name, 'className', 160),
  subject: requiredText(academicClass?.subject, 'subject', 120),
  grade: optionalText(academicClass?.grade, 'grade', 64),
  teacherDisplayName: optionalText(teacherDisplayName, 'teacherDisplayName', 160),
  room: optionalText(academicClass?.roomOrLocation, 'room', 120),
  normalSchedule: schedule({
    daysOfWeek: academicClass?.daysOfWeek,
    startTime: academicClass?.startTime,
    endTime: academicClass?.endTime,
    room: academicClass?.roomOrLocation,
  }),
  effectiveSchedule: schedule(effectiveSchedule),
  active: academicClass?.active === true && academicClass?.status !== 'archived',
  sourceVersion: normalizeSourceVersion(sourceVersion),
});

const attendanceStatuses = new Set(['present', 'absent', 'late', 'excused']);
const presenceStates = new Set(['unknown', 'outside', 'inside', 'departed']);

export const attendanceProjection = ({ record, sourceVersion }) => {
  if (!attendanceStatuses.has(record?.status)) throw new Error('Attendance status is invalid.');
  if (!presenceStates.has(record?.currentPresenceState)) throw new Error('Presence state is invalid.');
  const summaryId = requiredText(record.summaryId, 'summaryId', 200);
  if (record.attendanceDate == null) throw new Error('Attendance date is invalid.');
  return {
    summaryId,
    studentId: requiredText(record.studentId, 'studentId', 128),
    instituteId: requiredText(record.instituteId, 'instituteId', 128),
    classId: requiredText(record.classId, 'classId', 128),
    attendanceDate: record.attendanceDate,
    status: record.status,
    entryTime: record.entryTime ?? null,
    exitTime: record.exitTime ?? null,
    late: record.late === true,
    currentPresenceState: record.currentPresenceState,
    sourceVersion: normalizeSourceVersion(sourceVersion),
  };
};

const noticeTargets = new Set(['instituteParents', 'student', 'class']);
export const noticeProjection = ({ notice, sourceVersion }) => {
  if (!noticeTargets.has(notice?.targetType)) throw new Error('Notice targetType is invalid.');
  const studentIds = [...new Set((notice.targetStudentIds ?? []).map((value) => requiredText(value, 'studentId', 128)))];
  const classIds = [...new Set((notice.targetClassIds ?? []).map((value) => requiredText(value, 'classId', 128)))];
  if (notice.targetType === 'student' && studentIds.length === 0) throw new Error('Student notice requires a target.');
  if (notice.targetType === 'class' && classIds.length === 0) throw new Error('Class notice requires a target.');
  return {
    noticeId: requiredText(notice.noticeId, 'noticeId', 128),
    instituteId: requiredText(notice.instituteId, 'instituteId', 128),
    title: requiredText(notice.title, 'title', 160),
    message: requiredText(notice.message, 'message', 1200),
    priority: notice.priority === 'important' ? 'important' : 'normal',
    publishedAt: notice.publishedAt,
    expiresAt: notice.expiresAt ?? null,
    active: notice.active === true,
    targetType: notice.targetType,
    targetStudentIds: studentIds,
    targetClassIds: classIds,
    sourceVersion: normalizeSourceVersion(sourceVersion),
  };
};

export const institutePublicProjection = ({ institute, sourceVersion }) => ({
  instituteId: requiredText(institute?.instituteId, 'instituteId', 128),
  displayName: requiredText(institute?.name, 'displayName', 160),
  logoUrl: optionalText(institute?.publicLogoUrl, 'logoUrl', 500),
  publicPhone: optionalText(institute?.publicPhone, 'publicPhone', 32),
  publicEmail: optionalText(institute?.publicEmail, 'publicEmail', 254),
  publicAddress: optionalText(institute?.publicAddress, 'publicAddress', 500),
  status: institute?.status === 'active' ? 'active' : 'suspended',
  sourceVersion: normalizeSourceVersion(sourceVersion),
});

export const safeAuditPayload = ({ auditLogId, actorUid, actorRole = 'instituteAdmin', instituteId, action, targetType, targetId }) => ({
  auditLogId: requiredText(auditLogId, 'auditLogId', 128),
  actorUid: requiredText(actorUid, 'actorUid', 128),
  actorRole: requiredText(actorRole, 'actorRole', 40),
  instituteId: requiredText(instituteId, 'instituteId', 128),
  action: requiredText(action, 'action', 80),
  targetType: requiredText(targetType, 'targetType', 80),
  targetId: requiredText(targetId, 'targetId', 128),
  summary: requiredText(action.replaceAll(/([A-Z])/g, ' $1').trim(), 'summary', 160),
});
