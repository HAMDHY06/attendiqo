import { FieldValue } from 'firebase-admin/firestore';
import {
  assertNewerVersion,
  attendanceProjection,
  classProjection,
  deterministicAttendanceSummaryId,
  deterministicParentLinkId,
  institutePublicProjection,
  noticeProjection,
  safeAuditPayload,
  sanitizeRelationship,
  studentProjection,
  validateExistingLink,
  validateLinkSources,
} from './parent_projection_validation.mjs';

const versionOf = (data) => {
  if (Number.isSafeInteger(data?.sourceVersion)) return data.sourceVersion;
  if (typeof data?.updatedAt?.toMillis === 'function') return data.updatedAt.toMillis();
  throw new Error('Authoritative source is missing a stable version.');
};
const activeInstitute = (data) => data?.active === true && data?.status === 'active';
const activeAdmin = (data, instituteId) => data?.active === true
  && data?.role === 'instituteAdmin' && data?.instituteId === instituteId;
const activeParent = (data) => data?.active === true && data?.role === 'parent';
const sortedUnique = (values) => [...new Set(values)].sort();
const sameValues = (left = [], right = []) => JSON.stringify([...left].sort())
  === JSON.stringify([...right].sort());
const versionAcross = (source, documents = []) => Math.max(
  versionOf(source),
  ...documents.map((document) => versionOf(document.data())),
);
const timestampMillis = (value) => {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  throw new Error('Authoritative timestamp is invalid.');
};
const validatedAssignmentClasses = async ({ transaction, firestore, assignments, instituteId }) => {
  const activeAssignments = assignments.filter((item) => item.data()?.active === true);
  const classSnapshots = await Promise.all(activeAssignments.map((item) =>
    transaction.get(firestore.collection('classes').doc(item.data().classId))));
  return sortedUnique(classSnapshots.map((snapshot, index) => {
    const assignment = activeAssignments[index].data();
    const academicClass = snapshot.data();
    if (!snapshot.exists || assignment.instituteId !== instituteId
        || academicClass?.instituteId !== instituteId || academicClass?.active !== true
        || academicClass?.status === 'archived') {
      throw new Error('Cross-institute or inactive class assignment rejected.');
    }
    return assignment.classId;
  }));
};
const effectiveScheduleFrom = (changes, instituteId, classId, nowMs) => {
  const candidates = changes.filter((item) => {
    const value = item.data();
    if (value?.instituteId !== instituteId || value?.classId !== classId) {
      throw new Error('Cross-institute schedule change rejected.');
    }
    return value.status === 'scheduled'
      && timestampMillis(value.effectiveDate) + 86400000 > nowMs;
  }).sort((left, right) => timestampMillis(left.data().effectiveDate)
    - timestampMillis(right.data().effectiveDate));
  if (candidates.length === 0) return null;
  const value = candidates[0].data();
  return {
    daysOfWeek: [],
    startTime: value.newStartTime,
    endTime: value.newEndTime,
    room: value.newRoomOrLocation,
    effectiveDate: value.effectiveDate,
  };
};
const audit = (ref, values, fieldValue = FieldValue) => ({
  ...safeAuditPayload({ auditLogId: ref.id, ...values }),
  createdAt: fieldValue.serverTimestamp(),
});

export async function invalidateStudentLinksForInstituteMove({
  firestore, studentId, previousInstituteId, nextInstituteId,
  fieldValue = FieldValue,
}) {
  if (!studentId || !previousInstituteId || !nextInstituteId
      || previousInstituteId === nextInstituteId) {
    throw new Error('Student institute migration input is invalid.');
  }
  const linksQuery = firestore.collection('parent_student_links')
    .where('studentId', '==', studentId).where('active', '==', true);
  await firestore.runTransaction(async (transaction) => {
    const [studentSnap, linksSnap] = await Promise.all([
      transaction.get(firestore.collection('students').doc(studentId)),
      transaction.get(linksQuery),
    ]);
    if (!studentSnap.exists || studentSnap.data()?.instituteId !== nextInstituteId) {
      throw new Error('Authoritative student institute does not match migration target.');
    }
    const affected = linksSnap.docs.filter((item) => item.data().instituteId === previousInstituteId);
    const remainingByParent = await Promise.all(affected.map(async (link) => {
      const remainingSnap = await transaction.get(
        firestore.collection('parent_student_links')
          .where('parentUid', '==', link.data().parentUid).where('active', '==', true),
      );
      const remaining = remainingSnap.docs.filter((item) => item.id !== link.id);
      const profiles = await Promise.all(remaining.map((item) =>
        transaction.get(firestore.collection('parent_student_profiles').doc(item.data().studentId))));
      return { link, remaining, profiles };
    }));
    for (const { link, remaining, profiles } of remainingByParent) {
      const parentUid = link.data().parentUid;
      const auditRef = firestore.collection('audit_logs').doc();
      transaction.update(link.ref, {
        active: false, updatedAt: fieldValue.serverTimestamp(),
        revokedAt: fieldValue.serverTimestamp(), revokedBy: 'trusted-projection-sync',
      });
      transaction.set(firestore.collection('parent_access_scopes').doc(parentUid), {
        parentUid, active: remaining.length > 0,
        studentIds: remaining.map((item) => item.data().studentId),
        classIds: [...new Set(profiles.flatMap((item) => item.data()?.classIds ?? []))],
        instituteIds: [...new Set(remaining.map((item) => item.data().instituteId))],
        updatedAt: fieldValue.serverTimestamp(),
      });
      transaction.set(firestore.collection('users').doc(parentUid), {
        parentLinkedStudentIds: sortedUnique(
          remaining.map((item) => item.data().studentId),
        ),
      }, { merge: true });
      transaction.create(auditRef, audit(auditRef, {
        actorUid: 'trusted-projection-sync', actorRole: 'system',
        instituteId: previousInstituteId, action: 'parentLinkRevokedForInstituteMove',
        targetType: 'student', targetId: studentId,
      }, fieldValue));
    }
  });
}

async function authorizedSources(transaction, firestore, actorUid, instituteId, trustedSystem = false) {
  const [actorSnap, instituteSnap] = await Promise.all([
    transaction.get(firestore.collection('users').doc(actorUid)),
    transaction.get(firestore.collection('institutes').doc(instituteId)),
  ]);
  if (!trustedSystem && !activeAdmin(actorSnap.data(), instituteId)) throw new Error('Actor is not an active same-institute Admin.');
  if (!activeInstitute(instituteSnap.data())) throw new Error('Institute is not active.');
}

export async function upsertParentLink({ firestore, actorUid, parentUid, studentId, relationship, reactivate = false, fieldValue = FieldValue }) {
  const linkRef = firestore.collection('parent_student_links').doc(deterministicParentLinkId(parentUid, studentId));
  const studentProjectionRef = firestore.collection('parent_student_profiles').doc(studentId);
  const accessRef = firestore.collection('parent_access_scopes').doc(parentUid);
  const auditRef = firestore.collection('audit_logs').doc();
  const assignmentsQuery = firestore.collection('class_students')
    .where('studentId', '==', studentId);
  const activeLinksQuery = firestore.collection('parent_student_links')
    .where('parentUid', '==', parentUid).where('active', '==', true);
  await firestore.runTransaction(async (transaction) => {
    const [actorSnap, parentSnap, studentSnap, linkSnap, projectionSnap, accessSnap, assignmentsSnap, activeLinksSnap] = await Promise.all([
      transaction.get(firestore.collection('users').doc(actorUid)),
      transaction.get(firestore.collection('users').doc(parentUid)),
      transaction.get(firestore.collection('students').doc(studentId)),
      transaction.get(linkRef),
      transaction.get(studentProjectionRef), transaction.get(accessRef),
      transaction.get(assignmentsQuery),
      transaction.get(activeLinksQuery),
    ]);
    const student = studentSnap.data();
    if (!studentSnap.exists) throw new Error('Student does not exist.');
    const instituteSnap = await transaction.get(firestore.collection('institutes').doc(student.instituteId));
    validateLinkSources({
      actor: actorSnap.data(), parent: parentSnap.data(), student,
      institute: instituteSnap.data(),
    });
    const existing = linkSnap.data();
    const auditAction = validateExistingLink({
      existing, instituteId: student.instituteId, reactivate,
    });
    const sourceVersion = versionAcross(student, assignmentsSnap.docs);
    assertNewerVersion(projectionSnap.data()?.sourceVersion, sourceVersion);
    const classIds = await validatedAssignmentClasses({
      transaction, firestore, assignments: assignmentsSnap.docs,
      instituteId: student.instituteId,
    });
    const otherLinks = activeLinksSnap.docs.filter((item) => item.id !== linkRef.id);
    const otherProfiles = await Promise.all(otherLinks.map((item) =>
      transaction.get(firestore.collection('parent_student_profiles').doc(item.data().studentId))));
    const expectedScope = {
      studentIds: sortedUnique([...otherLinks.map((item) => item.data().studentId), studentId]),
      classIds: sortedUnique([
        ...otherProfiles.flatMap((item) => item.data()?.classIds ?? []),
        ...classIds,
      ]),
      instituteIds: sortedUnique([
        ...otherLinks.map((item) => item.data().instituteId),
        student.instituteId,
      ]),
    };
    const values = {
      parentUid, studentId, instituteId: student.instituteId,
      relationship: sanitizeRelationship(relationship), active: true,
      createdAt: existing?.createdAt ?? fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(), createdBy: existing?.createdBy ?? actorUid,
      revokedAt: null, revokedBy: null, sourceVersion,
    };
    const unchanged = existing?.active === true
      && existing.relationship === values.relationship
      && existing.sourceVersion === sourceVersion
      && projectionSnap.data()?.sourceVersion === sourceVersion
      && sameValues(projectionSnap.data()?.classIds, classIds)
      && accessSnap.data()?.active === true
      && sameValues(accessSnap.data()?.studentIds, expectedScope.studentIds)
      && sameValues(accessSnap.data()?.classIds, expectedScope.classIds)
      && sameValues(accessSnap.data()?.instituteIds, expectedScope.instituteIds)
      && sameValues(parentSnap.data()?.parentLinkedStudentIds, expectedScope.studentIds);
    if (unchanged) return;
    transaction.set(linkRef, values);
    transaction.set(studentProjectionRef, {
      ...studentProjection({ student, classIds, sourceVersion }),
      updatedAt: fieldValue.serverTimestamp(),
    });
    transaction.set(accessRef, {
      parentUid, active: true,
      ...expectedScope,
      updatedAt: fieldValue.serverTimestamp(),
    });
    transaction.set(firestore.collection('users').doc(parentUid), {
      parentLinkedStudentIds: expectedScope.studentIds,
    }, { merge: true });
    if (auditAction) {
      transaction.create(auditRef, audit(auditRef, {
        actorUid, instituteId: student.instituteId, action: auditAction,
        targetType: 'student', targetId: studentId,
      }, fieldValue));
    }
  });
}

export async function revokeParentLink({ firestore, actorUid, parentUid, studentId, fieldValue = FieldValue }) {
  const linkRef = firestore.collection('parent_student_links').doc(deterministicParentLinkId(parentUid, studentId));
  const accessRef = firestore.collection('parent_access_scopes').doc(parentUid);
  const auditRef = firestore.collection('audit_logs').doc();
  const linksQuery = firestore.collection('parent_student_links')
    .where('parentUid', '==', parentUid).where('active', '==', true);
  await firestore.runTransaction(async (transaction) => {
    const [linkSnap, linksSnap] = await Promise.all([
      transaction.get(linkRef), transaction.get(linksQuery),
    ]);
    if (!linkSnap.exists) return;
    const link = linkSnap.data();
    await authorizedSources(transaction, firestore, actorUid, link.instituteId);
    if (link.active === false) return;
    const remainingLinks = linksSnap.docs.filter((item) => item.id !== linkRef.id);
    const remainingProfiles = await Promise.all(remainingLinks.map((item) =>
      transaction.get(firestore.collection('parent_student_profiles').doc(item.data().studentId))));
    const studentIds = remainingLinks.map((item) => item.data().studentId);
    const instituteIds = [...new Set(remainingLinks.map((item) => item.data().instituteId))];
    const classIds = [...new Set(remainingProfiles.flatMap((item) => item.data()?.classIds ?? []))];
    transaction.update(linkRef, {
      active: false, updatedAt: fieldValue.serverTimestamp(),
      revokedAt: fieldValue.serverTimestamp(), revokedBy: actorUid,
    });
    transaction.set(accessRef, {
      parentUid, active: studentIds.length > 0, studentIds, classIds,
      instituteIds, updatedAt: fieldValue.serverTimestamp(),
    });
    transaction.set(firestore.collection('users').doc(parentUid), {
      parentLinkedStudentIds: sortedUnique(studentIds),
    }, { merge: true });
    transaction.create(auditRef, audit(auditRef, {
      actorUid, instituteId: link.instituteId, action: 'parentLinkRevoked',
      targetType: 'student', targetId: studentId,
    }, fieldValue));
  });
}

export async function syncStudentProjection({ firestore, actorUid, studentId, trustedSystem = false, fieldValue = FieldValue }) {
  const sourceRef = firestore.collection('students').doc(studentId);
  const projectionRef = firestore.collection('parent_student_profiles').doc(studentId);
  const [sourceBeforeSync, projectionBeforeSync] = await Promise.all([
    sourceRef.get(), projectionRef.get(),
  ]);
  if (sourceBeforeSync.exists && projectionBeforeSync.exists
      && sourceBeforeSync.data().instituteId !== projectionBeforeSync.data().instituteId) {
    await invalidateStudentLinksForInstituteMove({
      firestore, studentId,
      previousInstituteId: projectionBeforeSync.data().instituteId,
      nextInstituteId: sourceBeforeSync.data().instituteId,
      fieldValue,
    });
  }
  const assignmentsQuery = firestore.collection('class_students')
    .where('studentId', '==', studentId);
  const activeLinksQuery = firestore.collection('parent_student_links')
    .where('studentId', '==', studentId).where('active', '==', true);
  const auditRef = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    const [sourceSnap, projectionSnap, assignmentsSnap, activeLinksSnap] = await Promise.all([
      transaction.get(sourceRef), transaction.get(projectionRef),
      transaction.get(assignmentsQuery), transaction.get(activeLinksQuery),
    ]);
    if (!sourceSnap.exists) throw new Error('Student source does not exist.');
    const student = sourceSnap.data();
    await authorizedSources(transaction, firestore, actorUid, student.instituteId, trustedSystem);
    const classIds = await validatedAssignmentClasses({
      transaction, firestore, assignments: assignmentsSnap.docs,
      instituteId: student.instituteId,
    });
    const sourceVersion = versionAcross(student, assignmentsSnap.docs);
    assertNewerVersion(projectionSnap.data()?.sourceVersion, sourceVersion);
    if (projectionSnap.exists && projectionSnap.data().sourceVersion === sourceVersion) return;
    const affectedParents = await Promise.all(activeLinksSnap.docs.map(async (link) => {
      const parentUid = link.data().parentUid;
      const allLinksSnap = await transaction.get(
        firestore.collection('parent_student_links')
          .where('parentUid', '==', parentUid).where('active', '==', true),
      );
      const otherLinks = allLinksSnap.docs.filter((item) => item.data().studentId !== studentId);
      const otherProfiles = await Promise.all(otherLinks.map((item) =>
        transaction.get(firestore.collection('parent_student_profiles').doc(item.data().studentId))));
      return {
        parentUid,
        studentIds: sortedUnique([
          ...otherLinks.map((item) => item.data().studentId),
          studentId,
        ]),
        classIds: sortedUnique([
          ...otherProfiles.flatMap((item) => item.data()?.classIds ?? []),
          ...classIds,
        ]),
        instituteIds: sortedUnique([
          ...otherLinks.map((item) => item.data().instituteId),
          student.instituteId,
        ]),
      };
    }));
    const value = studentProjection({ student, classIds, sourceVersion });
    transaction.set(projectionRef, { ...value, updatedAt: fieldValue.serverTimestamp() });
    for (const scope of affectedParents) {
      transaction.set(firestore.collection('parent_access_scopes').doc(scope.parentUid), {
        parentUid: scope.parentUid,
        active: true,
        studentIds: scope.studentIds,
        classIds: scope.classIds,
        instituteIds: scope.instituteIds,
        updatedAt: fieldValue.serverTimestamp(),
      });
      transaction.set(firestore.collection('users').doc(scope.parentUid), {
        parentLinkedStudentIds: scope.studentIds,
      }, { merge: true });
    }
    transaction.create(auditRef, audit(auditRef, {
      actorUid, instituteId: student.instituteId, action: 'parentStudentProjectionUpdated',
      targetType: 'student', targetId: studentId,
    }, fieldValue));
  });
}

export async function syncClassProjection({ firestore, actorUid, classId, trustedSystem = false, nowMs = Date.now(), fieldValue = FieldValue }) {
  const sourceRef = firestore.collection('classes').doc(classId);
  const projectionRef = firestore.collection('parent_class_profiles').doc(classId);
  const auditRef = firestore.collection('audit_logs').doc();
  const scheduleQuery = firestore.collection('class_schedule_changes')
    .where('classId', '==', classId);
  await firestore.runTransaction(async (transaction) => {
    const [sourceSnap, projectionSnap, scheduleSnap] = await Promise.all([
      transaction.get(sourceRef), transaction.get(projectionRef), transaction.get(scheduleQuery),
    ]);
    if (!sourceSnap.exists) throw new Error('Class source does not exist.');
    const source = sourceSnap.data();
    await authorizedSources(transaction, firestore, actorUid, source.instituteId, trustedSystem);
    let teacherDisplayName = null;
    if (source.primaryTeacherId) {
      const teacherSnap = await transaction.get(firestore.collection('users').doc(source.primaryTeacherId));
      const teacher = teacherSnap.data();
      if (teacher?.role !== 'teacher' || teacher?.instituteId !== source.instituteId) throw new Error('Cross-institute teacher rejected.');
      teacherDisplayName = teacher.displayName;
    }
    const effectiveSchedule = effectiveScheduleFrom(
      scheduleSnap.docs, source.instituteId, classId, nowMs,
    );
    const sourceVersion = versionAcross(source, scheduleSnap.docs);
    assertNewerVersion(projectionSnap.data()?.sourceVersion, sourceVersion);
    if (projectionSnap.exists && projectionSnap.data().sourceVersion === sourceVersion) return;
    const value = classProjection({ academicClass: source, teacherDisplayName, effectiveSchedule, sourceVersion });
    transaction.set(projectionRef, { ...value, updatedAt: fieldValue.serverTimestamp() });
    transaction.create(auditRef, audit(auditRef, {
      actorUid, instituteId: source.instituteId, action: 'parentClassProjectionUpdated',
      targetType: 'academicClass', targetId: classId,
    }, fieldValue));
  });
}

export async function syncAttendanceProjection({
  firestore, sourceRecordId, actorUid = 'trusted-attendance-sync',
  sourceCollection = 'attendance_records', fieldValue = FieldValue,
}) {
  const sourceRef = firestore.collection(sourceCollection).doc(sourceRecordId);
  const auditRef = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    const sourceSnap = await transaction.get(sourceRef);
    if (!sourceSnap.exists) throw new Error('Attendance source does not exist.');
    const source = sourceSnap.data();
    const [studentSnap, classSnap, instituteSnap] = await Promise.all([
      transaction.get(firestore.collection('students').doc(source.studentId)),
      transaction.get(firestore.collection('classes').doc(source.classId)),
      transaction.get(firestore.collection('institutes').doc(source.instituteId)),
    ]);
    if (!studentSnap.exists || !classSnap.exists || !activeInstitute(instituteSnap.data())
        || studentSnap.data()?.instituteId !== source.instituteId
        || classSnap.data()?.instituteId !== source.instituteId
        || studentSnap.data()?.active !== true || classSnap.data()?.active !== true
        || classSnap.data()?.status === 'archived') {
      throw new Error('Cross-institute or inactive attendance source rejected.');
    }
    const sourceVersion = versionOf(source);
    const summaryId = deterministicAttendanceSummaryId(
      source.studentId,
      source.attendanceDateKey,
      source.classId,
    );
    if (source.summaryId != null && source.summaryId !== summaryId) {
      throw new Error('Attendance summary ID is invalid.');
    }
    const projectionRef = firestore.collection('parent_attendance_summaries').doc(summaryId);
    const projectionSnap = await transaction.get(projectionRef);
    assertNewerVersion(projectionSnap.data()?.sourceVersion, sourceVersion);
    if (projectionSnap.exists && projectionSnap.data().sourceVersion === sourceVersion) return;
    const value = attendanceProjection({ record: { ...source, summaryId }, sourceVersion });
    transaction.set(projectionRef, { ...value, updatedAt: fieldValue.serverTimestamp() });
    transaction.create(auditRef, audit(auditRef, {
      actorUid, actorRole: actorUid === 'trusted-attendance-sync' ? 'system' : 'instituteAdmin',
      instituteId: source.instituteId, action: 'parentAttendanceProjectionUpdated',
      targetType: 'attendance', targetId: summaryId,
    }, fieldValue));
  });
}

export async function publishParentNotice({ firestore, actorUid, notice, fieldValue = FieldValue }) {
  const sanitized = noticeProjection({
    notice: { ...notice, publishedAt: null },
    sourceVersion: Number.isSafeInteger(notice.sourceVersion) ? notice.sourceVersion : 0,
  });
  const projectionRef = firestore.collection('parent_notices').doc(sanitized.noticeId);
  const auditRef = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    await authorizedSources(transaction, firestore, actorUid, sanitized.instituteId);
    const [studentTargets, classTargets] = await Promise.all([
      Promise.all(sanitized.targetStudentIds.map((id) =>
        transaction.get(firestore.collection('students').doc(id)))),
      Promise.all(sanitized.targetClassIds.map((id) =>
        transaction.get(firestore.collection('classes').doc(id)))),
    ]);
    if (studentTargets.some((snap) => !snap.exists || snap.data()?.active !== true
        || snap.data()?.instituteId !== sanitized.instituteId)
      || classTargets.some((snap) => !snap.exists || snap.data()?.active !== true
        || snap.data()?.status === 'archived'
        || snap.data()?.instituteId !== sanitized.instituteId)) {
      throw new Error('Notice target is missing or cross-institute.');
    }
    const existing = await transaction.get(projectionRef);
    const sourceVersion = notice.sourceVersion == null
      ? (existing.data()?.sourceVersion ?? 0) + 1
      : notice.sourceVersion;
    assertNewerVersion(existing.data()?.sourceVersion, sourceVersion);
    if (existing.exists && existing.data().sourceVersion === sourceVersion) return;
    const value = {
      ...sanitized,
      sourceVersion,
      publishedAt: existing.data()?.publishedAt ?? fieldValue.serverTimestamp(),
    };
    transaction.set(projectionRef, { ...value, updatedAt: fieldValue.serverTimestamp() });
    transaction.create(auditRef, audit(auditRef, {
      actorUid, instituteId: value.instituteId,
      action: existing.exists ? 'parentNoticeUpdated' : 'parentNoticePublished',
      targetType: 'notice', targetId: value.noticeId,
    }, fieldValue));
  });
}

export async function syncInstitutePublicProfile({
  firestore, actorUid, instituteId, trustedSystem = false, fieldValue = FieldValue,
}) {
  const sourceRef = firestore.collection('institutes').doc(instituteId);
  const projectionRef = firestore.collection('institute_public_profiles').doc(instituteId);
  const auditRef = firestore.collection('audit_logs').doc();
  await firestore.runTransaction(async (transaction) => {
    const [sourceSnap, projectionSnap] = await Promise.all([
      transaction.get(sourceRef), transaction.get(projectionRef),
    ]);
    if (!sourceSnap.exists) throw new Error('Institute source does not exist.');
    const source = sourceSnap.data();
    if (!trustedSystem) await authorizedSources(transaction, firestore, actorUid, instituteId);
    const sourceVersion = versionOf(source);
    assertNewerVersion(projectionSnap.data()?.sourceVersion, sourceVersion);
    if (projectionSnap.exists && projectionSnap.data().sourceVersion === sourceVersion) return;
    const value = institutePublicProjection({ institute: source, sourceVersion });
    transaction.set(projectionRef, { ...value, updatedAt: fieldValue.serverTimestamp() });
    transaction.create(auditRef, audit(auditRef, {
      actorUid: trustedSystem ? 'trusted-projection-sync' : actorUid,
      actorRole: trustedSystem ? 'system' : 'instituteAdmin',
      instituteId, action: 'institutePublicProfileUpdated',
      targetType: 'institute', targetId: instituteId,
    }, fieldValue));
  });
}
