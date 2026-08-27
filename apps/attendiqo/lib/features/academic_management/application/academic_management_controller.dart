import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

enum AcademicClassFilter { all, active, inactive, archived }

class AcademicManagementController extends ChangeNotifier {
  AcademicManagementController({
    required this.actor,
    required this.repository,
    StudentQrService? qrService,
  }) : qrService = qrService ?? SecureStudentQrService();
  UserProfile actor;
  final AcademicRepository repository;
  final StudentQrService qrService;
  List<AcademicClass> classes = [];
  List<Student> students = [];
  List<UserProfile> teachers = [];
  List<ClassScheduleChange> scheduleChanges = [];
  List<ClassStudentAssignment> assignments = [];
  List<AuditLogEntry> auditLogs = [];
  bool loading = false;
  bool saving = false;
  String? error;
  String classSearch = '';
  String studentSearch = '';
  AcademicClassFilter classFilter = AcademicClassFilter.all;
  String? classTeacherFilter;
  String? classSubjectFilter;
  String? classGradeFilter;
  StudentStatus? studentStatusFilter;
  String? classStudentFilter;
  String? lastCreatedQrPayload;

  bool get isInstituteAdmin => actor.role == UserRole.instituteAdmin;
  bool get isTeacher => actor.role == UserRole.teacher;
  bool get canCreateClass => AcademicAuthorization.canCreateClasses(actor);
  bool get canCreateStudentDirectly =>
      actor.instituteId != null &&
      AcademicAuthorization.canCreateStudent(actor, actor.instituteId!);
  bool get requestsTeacherStudentBackend =>
      isTeacher &&
      (actor.effectiveTeacherPermissions.canAddStudents ||
          actor.effectiveTeacherPermissions.canEditStudents);

  bool canEditClass(AcademicClass value) =>
      AcademicAuthorization.canEditClass(actor, value);
  bool canChangeClassStatus(AcademicClass value) =>
      AcademicAuthorization.canChangeClassStatus(actor, value);
  bool canAssignTeachers(AcademicClass value) =>
      AcademicAuthorization.canAssignTeachers(actor, value);
  bool canEditStudent(Student value) => AcademicAuthorization.canEditStudent(
    actor,
    value,
    assignedClasses: classes,
  );
  bool canAssignStudents(AcademicClass value) =>
      AcademicAuthorization.canAssignStudents(actor, value);

  List<AcademicClass> get visibleClasses => classes.where((value) {
    final query = classSearch.toLowerCase().trim();
    final search =
        query.isEmpty ||
        value.name.toLowerCase().contains(query) ||
        value.classCode.toLowerCase().contains(query) ||
        value.subject.toLowerCase().contains(query) ||
        (value.grade?.toLowerCase().contains(query) ?? false);
    final status =
        classFilter == AcademicClassFilter.all ||
        classFilter.name == value.status.name;
    final teacher =
        classTeacherFilter == null ||
        value.teacherIds.contains(classTeacherFilter);
    final subject =
        classSubjectFilter == null || value.subject == classSubjectFilter;
    final grade = classGradeFilter == null || value.grade == classGradeFilter;
    return search && status && teacher && subject && grade;
  }).toList();

  List<Student> get visibleStudents => students.where((value) {
    final query = studentSearch.toLowerCase().trim();
    final search =
        query.isEmpty ||
        value.fullName.toLowerCase().contains(query) ||
        value.studentNumber.toLowerCase().contains(query) ||
        value.primaryParentMobile.toLowerCase().contains(query);
    final status =
        studentStatusFilter == null || studentStatusFilter == value.status;
    final classMatch =
        classStudentFilter == null ||
        assignments.any(
          (a) =>
              a.classId == classStudentFilter &&
              a.studentId == value.studentId &&
              a.active,
        );
    return search && status && classMatch;
  }).toList();

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final instituteId = actor.role == UserRole.superAdmin
          ? null
          : actor.instituteId;
      final results = await Future.wait([
        repository.fetchClasses(actor),
        repository.fetchStudents(actor),
        repository.fetchTeachersForAcademic(actor),
        repository.fetchScheduleChanges(actor),
        repository.fetchAssignments(actor),
        actor.role == UserRole.teacher
            ? Future<List<AuditLogEntry>>.value(const [])
            : repository.fetchAuditLogs(instituteId: instituteId),
      ]);
      classes = results[0] as List<AcademicClass>;
      students = results[1] as List<Student>;
      teachers = results[2] as List<UserProfile>;
      if (actor.role == UserRole.teacher && teachers.isNotEmpty) {
        actor = teachers.first;
      }
      scheduleChanges = results[3] as List<ClassScheduleChange>;
      assignments = results[4] as List<ClassStudentAssignment>;
      auditLogs = results[5] as List<AuditLogEntry>;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to load classes and students. Please try again.',
      );
      _debugFailure('load', failure.code, failure.runtimeType);
    } catch (exception) {
      error = 'Unable to load classes and students. Please try again.';
      _debugFailure('load', null, exception.runtimeType);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshClasses() async {
    try {
      classes = await repository.fetchClasses(actor);
      notifyListeners();
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'The class list could not be refreshed.',
      );
      _debugFailure('refreshClasses', failure.code, failure.runtimeType);
      notifyListeners();
    } catch (exception) {
      error = 'The class list could not be refreshed.';
      _debugFailure('refreshClasses', null, exception.runtimeType);
      notifyListeners();
    }
  }

  void setClassSearch(String value) {
    classSearch = value;
    notifyListeners();
  }

  void setStudentSearch(String value) {
    studentSearch = value;
    notifyListeners();
  }

  void setClassFilter(AcademicClassFilter value) {
    classFilter = value;
    notifyListeners();
  }

  void setClassTeacherFilter(String? value) {
    classTeacherFilter = value;
    notifyListeners();
  }

  void setClassSubjectFilter(String? value) {
    classSubjectFilter = value;
    notifyListeners();
  }

  void setClassGradeFilter(String? value) {
    classGradeFilter = value;
    notifyListeners();
  }

  void setStudentStatusFilter(StudentStatus? value) {
    studentStatusFilter = value;
    notifyListeners();
  }

  void setClassStudentFilter(String? value) {
    classStudentFilter = value;
    notifyListeners();
  }

  Future<AcademicClass?> createClass({
    required String code,
    required String name,
    required String subject,
    String? grade,
    required LocalTime start,
    required LocalTime end,
    required Set<ClassWeekday> days,
    String room = '',
    required int academicYear,
    required List<String> teacherIds,
    String? primaryTeacherId,
  }) async {
    if (saving) return null;
    final instituteId = actor.instituteId;
    if (instituteId == null) {
      error = 'Select an institute before creating a class.';
      notifyListeners();
      return null;
    }
    final effectiveTeacherIds = actor.role == UserRole.teacher
        ? <String>[actor.uid]
        : teacherIds;
    final effectivePrimaryTeacherId = actor.role == UserRole.teacher
        ? actor.uid
        : primaryTeacherId;
    final value = AcademicClass.newClass(
      classId: 'class-${DateTime.now().microsecondsSinceEpoch}',
      instituteId: instituteId,
      classCode: code,
      name: name,
      subject: subject,
      grade: grade,
      primaryTeacherId: effectivePrimaryTeacherId,
      teacherIds: effectiveTeacherIds,
      daysOfWeek: days,
      startTime: start,
      endTime: end,
      roomOrLocation: room,
      academicYear: academicYear,
      now: DateTime.now().toUtc(),
      actorUid: actor.uid,
    );
    final validation = value.validate();
    if (validation != null ||
        days.isEmpty ||
        academicYear < 2000 ||
        academicYear > 2200) {
      error =
          validation ??
          (days.isEmpty
              ? 'Select at least one class day.'
              : 'Academic year must be between 2000 and 2200.');
      notifyListeners();
      return null;
    }
    if (!AcademicAuthorization.canCreateClass(actor, value.instituteId)) {
      error = 'You do not have permission to create classes.';
      notifyListeners();
      return null;
    }
    return _save(
      () => repository.createClass(value, actor),
      onSuccess: (created) {
        classes = [...classes, created]
          ..sort((a, b) => a.name.compareTo(b.name));
      },
    );
  }

  Future<bool> updateClass(AcademicClass value) async {
    if (!AcademicAuthorization.canEditClass(actor, value)) {
      error = value.status == AcademicClassStatus.archived
          ? 'Archived classes cannot be edited by a Teacher.'
          : 'You may edit only classes assigned to you with Edit Classes permission.';
      notifyListeners();
      return false;
    }
    if (actor.role == UserRole.teacher &&
        (value.teacherIds.length != 1 ||
            value.teacherIds.single != actor.uid ||
            value.primaryTeacherId != actor.uid)) {
      error = 'Teacher assignments can be changed only by an Institute Admin.';
      notifyListeners();
      return false;
    }
    final result = await _save(
      () async {
        await repository.updateClass(value, actor);
        return value;
      },
      onSuccess: (updated) {
        final index = classes.indexWhere((e) => e.classId == updated.classId);
        if (index >= 0) classes[index] = updated;
      },
    );
    return result != null;
  }

  Future<Student?> createStudent({
    required String studentNumber,
    required String fullName,
    String? preferredName,
    required String primaryParentName,
    required String primaryParentMobile,
    String? secondaryParentName,
    String? secondaryParentMobile,
    String? parentEmail,
    String address = '',
    String? emergencyContactName,
    String? emergencyContactMobile,
  }) async {
    if (saving) return null;
    if (actor.uid.trim().isEmpty) {
      error = 'Your account profile is unavailable. Please sign in again.';
      notifyListeners();
      return null;
    }
    final instituteId = actor.instituteId;
    if (instituteId == null || instituteId.trim().isEmpty) {
      error = 'Your account is not assigned to an institute.';
      notifyListeners();
      return null;
    }
    final inputError =
        StudentNumberValidator.validate(studentNumber) ??
        FieldValidators.required(fullName, label: 'Full name') ??
        FieldValidators.required(
          primaryParentName,
          label: 'Primary parent/guardian name',
        ) ??
        MobileNumberValidator.validatePrimary(primaryParentMobile);
    if (inputError != null) {
      error = inputError;
      notifyListeners();
      return null;
    }
    if (!AcademicAuthorization.canCreateStudent(actor, instituteId)) {
      error =
          actor.role == UserRole.teacher &&
              actor.effectiveTeacherPermissions.canAddStudents
          ? 'Student creation requires the trusted student service, which is not configured yet.'
          : 'You do not have permission to create students.';
      notifyListeners();
      return null;
    }
    String? generatedQrPayload;
    return _save(
      () async {
        final studentId = 'student-${DateTime.now().microsecondsSinceEpoch}';
        final qr = qrService.generate(
          studentId: studentId,
          instituteId: instituteId,
          version: 1,
        );
        final now = DateTime.now().toUtc();
        final value = Student(
          studentId: studentId,
          instituteId: instituteId,
          studentNumber: StudentNumberValidator.normalize(studentNumber),
          fullName: fullName.trim(),
          preferredName: _optionalText(preferredName),
          address: address.trim(),
          primaryParentName: primaryParentName.trim(),
          primaryParentMobile: MobileNumberValidator.normalize(
            primaryParentMobile,
          ),
          secondaryParentName: _optionalText(secondaryParentName),
          secondaryParentMobile: _optionalMobile(secondaryParentMobile),
          parentEmail: _optionalText(parentEmail)?.toLowerCase(),
          emergencyContactName: _optionalText(emergencyContactName),
          emergencyContactMobile: _optionalMobile(emergencyContactMobile),
          status: StudentStatus.active,
          active: true,
          qrToken: qr.credential.tokenHash,
          qrVersion: 1,
          qrEnabled: true,
          createdAt: now,
          createdBy: actor.uid,
          updatedAt: now,
          updatedBy: actor.uid,
        );
        generatedQrPayload = qr.payload;
        return repository.createStudent(value, actor);
      },
      onSuccess: (created) {
        students = [...students, created]
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
        lastCreatedQrPayload = generatedQrPayload;
      },
    );
  }

  String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _optionalMobile(String? value) {
    final normalized = _optionalText(value);
    return normalized == null
        ? null
        : MobileNumberValidator.normalize(normalized);
  }

  Future<bool> updateStudent(Student value) async {
    if (!AcademicAuthorization.canEditStudent(
      actor,
      value,
      assignedClasses: classes,
    )) {
      error =
          actor.role == UserRole.teacher &&
              actor.effectiveTeacherPermissions.canEditStudents
          ? 'Student editing requires the trusted assigned-student service, which is not configured yet.'
          : 'You do not have permission to edit this student.';
      notifyListeners();
      return false;
    }
    final result = await _save(
      () async {
        await repository.updateStudent(value, actor);
        return value;
      },
      onSuccess: (updated) {
        final index = students.indexWhere(
          (e) => e.studentId == updated.studentId,
        );
        if (index >= 0) students[index] = updated;
      },
    );
    return result != null;
  }

  List<ScheduleOverlap> overlapsFor(String studentId, AcademicClass candidate) {
    final assignedIds = assignments
        .where((a) => a.studentId == studentId && a.active)
        .map((a) => a.classId)
        .toSet();
    return ScheduleOverlapDetector.detect(
      candidate,
      classes.where((c) => assignedIds.contains(c.classId)),
    );
  }

  Future<bool> assignStudent({
    required Student student,
    required AcademicClass academicClass,
    bool overlapConfirmed = false,
    String? overlapReason,
  }) async {
    if (!AcademicAuthorization.canAssignStudents(actor, academicClass)) {
      error = 'Only an Institute Admin can manage class enrolments.';
      notifyListeners();
      return false;
    }
    final overlaps = overlapsFor(student.studentId, academicClass);
    if (overlaps.isNotEmpty &&
        (!overlapConfirmed ||
            overlapReason == null ||
            overlapReason.trim().isEmpty)) {
      error = 'This class overlaps with another class assigned to the student.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now().toUtc();
    final assignment = ClassStudentAssignment(
      assignmentId: '${academicClass.classId}_${student.studentId}',
      instituteId: academicClass.instituteId,
      classId: academicClass.classId,
      studentId: student.studentId,
      active: true,
      joinedAt: now,
      joinedBy: actor.uid,
      status: ClassStudentAssignmentStatus.active,
      scheduleOverlapConfirmed: overlaps.isNotEmpty && overlapConfirmed,
      scheduleOverlapReason: overlaps.isNotEmpty ? overlapReason?.trim() : null,
      scheduleOverlapConfirmedBy: overlaps.isNotEmpty ? actor.uid : null,
      scheduleOverlapConfirmedAt: overlaps.isNotEmpty ? now : null,
    );
    final result = await _save(() async {
      await repository.saveAssignment(assignment, actor);
      return assignment;
    }, onSuccess: (value) => assignments.add(value));
    return result != null;
  }

  Future<bool> removeAssignment(ClassStudentAssignment assignment) async {
    final academicClass = classes
        .where((value) => value.classId == assignment.classId)
        .firstOrNull;
    if (academicClass == null ||
        !AcademicAuthorization.canAssignStudents(actor, academicClass)) {
      error = 'Only an Institute Admin can remove class enrolments.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now().toUtc();
    final removed = ClassStudentAssignment(
      assignmentId: assignment.assignmentId,
      instituteId: assignment.instituteId,
      classId: assignment.classId,
      studentId: assignment.studentId,
      active: false,
      joinedAt: assignment.joinedAt,
      joinedBy: assignment.joinedBy,
      leftAt: now,
      leftBy: actor.uid,
      status: ClassStudentAssignmentStatus.removed,
      scheduleOverlapConfirmed: assignment.scheduleOverlapConfirmed,
      scheduleOverlapReason: assignment.scheduleOverlapReason,
      scheduleOverlapConfirmedBy: assignment.scheduleOverlapConfirmedBy,
      scheduleOverlapConfirmedAt: assignment.scheduleOverlapConfirmedAt,
    );
    final result = await _save(
      () async {
        await repository.saveAssignment(removed, actor);
        return removed;
      },
      onSuccess: (value) {
        final index = assignments.indexWhere(
          (e) => e.assignmentId == value.assignmentId,
        );
        if (index >= 0) assignments[index] = value;
      },
    );
    return result != null;
  }

  Future<bool> saveScheduleChange(ClassScheduleChange change) async {
    final academicClass = classes
        .where((value) => value.classId == change.classId)
        .firstOrNull;
    if (academicClass == null ||
        !AcademicAuthorization.canManageScheduleChange(actor, academicClass)) {
      error = 'You cannot change the schedule for this class.';
      notifyListeners();
      return false;
    }
    final result = await _save(
      () async {
        await repository.saveScheduleChange(change, actor);
        return change;
      },
      onSuccess: (value) {
        final index = scheduleChanges.indexWhere(
          (e) => e.scheduleChangeId == value.scheduleChangeId,
        );
        if (index < 0) {
          scheduleChanges.add(value);
        } else {
          scheduleChanges[index] = value;
        }
      },
    );
    return result != null;
  }

  Future<T?> _save<T>(
    Future<T> Function() operation, {
    required void Function(T) onSuccess,
  }) async {
    if (saving) return null;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final result = await operation();
      onSuccess(result);
      return result;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to save changes. Please try again.',
      );
      _debugFailure('save', failure.code, failure.runtimeType);
      return null;
    } catch (exception) {
      error = 'Unable to save changes. Please try again.';
      _debugFailure('save', null, exception.runtimeType);
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  void _debugFailure(String operation, String? code, Type type) {
    if (kDebugMode) {
      debugPrint(
        '[AcademicManagement] $operation failed code=${code ?? 'unknown'} type=$type',
      );
    }
  }
}
