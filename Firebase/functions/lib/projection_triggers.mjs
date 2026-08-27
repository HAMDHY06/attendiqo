// REVIEW-ONLY trigger factory. Source documents are authoritative; projection
// output collections are never trigger sources, preventing write loops.
const sourceId = (event, field) => event.data?.after?.data()?.[field]
  ?? event.data?.before?.data()?.[field] ?? null;
const safeFailure = (name) => (error) => {
  // Deliberately no payload, document path, name, email, QR or token logging.
  console.error(JSON.stringify({ event: 'parent_projection_trigger_failed', trigger: name, severity: 'error', code: error?.code ?? 'internal' }));
};
const run = (name, operation) => async (event) => {
  try { await operation(event); } catch (error) { safeFailure(name)(error); throw error; }
};

export const createProjectionTriggers = ({ firestore, writers }) => ({
  onStudentWrite: run('student', async (event) => {
    const studentId = event.params.studentId;
    if (event.data?.after?.exists) await writers.syncStudentProjection({ firestore, actorUid: 'trusted-projection-trigger', studentId, trustedSystem: true });
  }),
  onClassWrite: run('class', async (event) => {
    const classId = event.params.classId;
    if (event.data?.after?.exists) await writers.syncClassProjection({ firestore, actorUid: 'trusted-projection-trigger', classId, trustedSystem: true });
  }),
  onAssignmentWrite: run('assignment', async (event) => {
    const studentId = sourceId(event, 'studentId');
    if (studentId) await writers.syncStudentProjection({ firestore, actorUid: 'trusted-projection-trigger', studentId, trustedSystem: true });
  }),
  onScheduleWrite: run('schedule', async (event) => {
    const classId = sourceId(event, 'classId');
    if (classId) await writers.syncClassProjection({ firestore, actorUid: 'trusted-projection-trigger', classId, trustedSystem: true });
  }),
  onAttendanceWrite: run('attendance', async (event) => {
    if (event.data?.after?.exists) await writers.syncAttendanceProjection({ firestore, sourceRecordId: event.params.recordId });
  }),
  onAttendanceCorrectionWrite: run('attendanceCorrection', async (event) => {
    const sourceRecordId = sourceId(event, 'attendanceRecordId') ?? sourceId(event, 'recordId');
    if (sourceRecordId) await writers.syncAttendanceProjection({ firestore, sourceRecordId });
  }),
  onInstituteWrite: run('institute', async (event) => {
    if (event.data?.after?.exists) await writers.syncInstitutePublicProfile({ firestore, actorUid: 'trusted-projection-trigger', instituteId: event.params.instituteId, trustedSystem: true });
  }),
});
