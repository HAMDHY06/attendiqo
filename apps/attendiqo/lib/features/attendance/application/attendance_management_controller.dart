import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

class AttendanceManagementController extends ChangeNotifier {
  AttendanceManagementController({
    required this.actor,
    required this.classes,
    required this.students,
    required this.assignments,
    required this.scheduleChanges,
    required this.service,
    required this.qrAdministrationService,
    this.backendAvailable = true,
    StudentQrService? qrService,
  }) : qrService = qrService ?? SecureStudentQrService();

  final UserProfile actor;
  final List<AcademicClass> classes;
  final List<Student> students;
  final List<ClassStudentAssignment> assignments;
  final List<ClassScheduleChange> scheduleChanges;
  final AttendanceService service;
  final QrAdministrationService qrAdministrationService;
  final bool backendAvailable;
  final StudentQrService qrService;
  final ScanCooldownGuard cooldown = ScanCooldownGuard();

  AcademicClass? selectedClass;
  AttendanceSession? session;
  AttendanceScanMode mode = AttendanceScanMode.entry;
  AttendanceScanResult? latest;
  final List<AttendanceRecord> records = [];
  bool paused = false;
  bool busy = false;
  bool online = true;
  String? error;
  String? oneTimeQrPayload;

  List<Student> get selectedClassStudents {
    final classId = selectedClass?.classId;
    if (classId == null) return const [];
    final ids = assignments
        .where((e) => e.classId == classId && e.active)
        .map((e) => e.studentId)
        .toSet();
    return students.where((e) => ids.contains(e.studentId)).toList();
  }

  int get scannedCount => records
      .where(
        (record) =>
            record.sessionId == session?.sessionId && record.entryTime != null,
      )
      .length;
  AttendanceSummary get summary => AttendanceSummary.from(
    records.where((record) => record.sessionId == session?.sessionId),
  );
  bool get scannerActive => session?.acceptsScans == true && !paused;
  List<AcademicClass> get attendanceClasses => classes
      .where(
        (value) => AttendanceAuthorization.canTakeClassAttendance(
          actor,
          value,
          trustedBackendAvailable: backendAvailable,
        ),
      )
      .toList();
  bool get canStartSelectedAttendance =>
      selectedClass != null &&
      AttendanceAuthorization.canTakeClassAttendance(
        actor,
        selectedClass!,
        trustedBackendAvailable: backendAvailable,
      );
  bool get canExportSelectedReport =>
      selectedClass != null &&
      AttendanceAuthorization.canExportClassReport(actor, selectedClass!);
  bool get canCorrectSelectedAttendance =>
      selectedClass != null &&
      AttendanceAuthorization.canCorrectClassAttendance(
        actor,
        selectedClass!,
        trustedBackendAvailable: backendAvailable,
      );
  bool get canManageSelectedClassQr => selectedClassStudents.any(
    (student) => AttendanceAuthorization.canGenerateStudentQr(
      actor,
      student,
      classes: classes,
      assignments: assignments,
      trustedBackendAvailable: backendAvailable,
    ),
  );

  void selectClass(AcademicClass? value) {
    selectedClass = value;
    session = null;
    latest = null;
    notifyListeners();
  }

  void setMode(AttendanceScanMode value) {
    mode = value;
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void setOnline(bool value) {
    online = value;
    notifyListeners();
  }

  Future<bool> startSession([DateTime? date]) async {
    final academicClass = selectedClass;
    if (academicClass == null) {
      error = 'Select a class first.';
      notifyListeners();
      return false;
    }
    if (!canStartSelectedAttendance) {
      error = backendAvailable
          ? 'You may take attendance only for an assigned active class.'
          : 'The trusted attendance backend is not configured.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final day = date ?? DateTime.now();
      final effective = ClassScheduleResolver.resolve(
        academicClass,
        day,
        scheduleChanges,
      );
      session = await service.startSession(
        academicClass: academicClass,
        schedule: effective,
        actor: actor,
        date: DateTime.utc(day.year, day.month, day.day),
        totalStudents: selectedClassStudents.length,
      );
      paused = false;
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to start attendance. Please try again.',
      );
      return false;
    } catch (_) {
      error = 'Unable to start attendance session.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<AttendanceScanResult> processPayload(
    String payload, {
    String deviceId = 'mobile-device',
  }) async {
    if (paused) {
      return const AttendanceScanResult(
        ScannerResultStatus.failure,
        'Scanner is paused.',
      );
    }
    final activeSession = session;
    if (activeSession == null) {
      return const AttendanceScanResult(
        ScannerResultStatus.closedSession,
        'Open a session first.',
      );
    }
    final hash = qrService.tokenHashFromPayload(payload);
    if (hash.isNotEmpty && !cooldown.shouldProcess(hash)) {
      latest = const AttendanceScanResult(
        ScannerResultStatus.cooldown,
        'Hold the QR away briefly before scanning again.',
      );
      notifyListeners();
      return latest!;
    }
    if (!online) {
      latest = const AttendanceScanResult(
        ScannerResultStatus.networkError,
        'No network. Attendance was not reported as confirmed.',
      );
      notifyListeners();
      return latest!;
    }
    busy = true;
    notifyListeners();
    try {
      latest = await service.recordScan(
        AttendanceScanRequest(
          payload: payload,
          session: activeSession,
          mode: mode,
          actor: actor,
          deviceId: deviceId,
        ),
      );
      final record = latest?.record;
      if (latest?.accepted == true && record != null) {
        final index = records.indexWhere(
          (e) => e.attendanceRecordId == record.attendanceRecordId,
        );
        if (index < 0) {
          records.add(record);
        } else {
          records[index] = record;
        }
      }
      return latest!;
    } on Failure catch (failure) {
      latest = AttendanceScanResult(
        ScannerResultStatus.failure,
        SafeErrorMapper.fromFailure(
          failure,
          fallback: 'Attendance could not be confirmed.',
        ),
      );
      return latest!;
    } catch (_) {
      latest = const AttendanceScanResult(
        ScannerResultStatus.failure,
        'Attendance could not be confirmed.',
      );
      return latest!;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> finishSession() async {
    final value = session;
    if (value == null) return false;
    busy = true;
    notifyListeners();
    try {
      session = await service.closeSession(value, actor);
      paused = true;
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to finish the attendance session.',
      );
      return false;
    } catch (_) {
      error = 'Unable to finish the attendance session.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancelSession() async {
    final value = session;
    if (value == null) return false;
    busy = true;
    notifyListeners();
    try {
      session = await service.cancelSession(value, actor);
      paused = true;
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to cancel the attendance session.',
      );
      return false;
    } catch (_) {
      error = 'Unable to cancel the attendance session.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> markManual(
    Student student,
    AttendanceStatus status,
    String reason,
  ) async {
    final value = session;
    if (value == null) return false;
    if (!canCorrectSelectedAttendance || reason.trim().isEmpty) {
      error = reason.trim().isEmpty
          ? 'A correction reason is required.'
          : 'You do not have permission to correct this class attendance.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final record = await service.recordManual(
        session: value,
        student: student,
        status: status,
        reason: reason,
        actor: actor,
      );
      final index = records.indexWhere(
        (e) => e.attendanceRecordId == record.attendanceRecordId,
      );
      if (index < 0) {
        records.add(record);
      } else {
        records[index] = record;
      }
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to save manual attendance.',
      );
      return false;
    } catch (_) {
      error = 'Unable to save manual attendance.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> correct(
    AttendanceRecord record,
    AttendanceStatus status,
    String reason, {
    DateTime? entryTime,
    DateTime? departureTime,
  }) async {
    final academicClass = classes
        .where((value) => value.classId == record.classId)
        .firstOrNull;
    if (academicClass == null ||
        !AttendanceAuthorization.canCorrectClassAttendance(
          actor,
          academicClass,
          reason: reason,
          trustedBackendAvailable: backendAvailable,
        )) {
      error = reason.trim().isEmpty
          ? 'A correction reason is required.'
          : 'You do not have permission to correct this attendance record.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = await service.correctRecord(
        record: record,
        status: status,
        reason: reason,
        actor: actor,
        entryTime: entryTime,
        departureTime: departureTime,
      );
      final index = records.indexWhere(
        (e) => e.attendanceRecordId == value.attendanceRecordId,
      );
      if (index >= 0) records[index] = value;
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to save the attendance correction.',
      );
      return false;
    } catch (_) {
      error = 'Unable to save the attendance correction.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<QrGenerationResult?> regenerateQr(Student student) async {
    if (!AttendanceAuthorization.canGenerateStudentQr(
      actor,
      student,
      classes: classes,
      assignments: assignments,
      trustedBackendAvailable: backendAvailable,
    )) {
      error = backendAvailable
          ? 'QR access is limited to students in your assigned classes.'
          : 'The trusted QR backend is not configured.';
      notifyListeners();
      return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await qrAdministrationService.regenerate(
        student: student,
        actor: actor,
      );
      oneTimeQrPayload = result.payload;
      final index = students.indexWhere(
        (e) => e.studentId == student.studentId,
      );
      if (index >= 0) {
        students[index] = student.copyWith(
          qrToken: result.credential.tokenHash,
          qrVersion: result.credential.version,
          qrEnabled: true,
          updatedAt: DateTime.now().toUtc(),
          updatedBy: actor.uid,
        );
      }
      return result;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to regenerate this QR code.',
      );
      return null;
    } catch (_) {
      error = 'Unable to regenerate this QR code.';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> setQrEnabled(Student student, bool enabled) async {
    if (!AttendanceAuthorization.canGenerateStudentQr(
      actor,
      student,
      classes: classes,
      assignments: assignments,
      trustedBackendAvailable: backendAvailable,
    )) {
      error = backendAvailable
          ? 'QR access is limited to students in your assigned classes.'
          : 'The trusted QR backend is not configured.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await qrAdministrationService.setEnabled(
        student: student,
        enabled: enabled,
        actor: actor,
      );
      final index = students.indexWhere(
        (e) => e.studentId == student.studentId,
      );
      if (index >= 0) {
        students[index] = student.copyWith(
          qrEnabled: enabled,
          updatedAt: DateTime.now().toUtc(),
          updatedBy: actor.uid,
        );
      }
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to update this QR code.',
      );
      return false;
    } catch (_) {
      error = 'Unable to update this QR code.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
