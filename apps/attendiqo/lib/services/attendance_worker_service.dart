import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Authenticated client for the trusted attendance and QR Worker. Only the
/// Firebase ID token crosses this boundary; service credentials stay server-side.
class AttendanceWorkerService
    implements AttendanceService, QrAdministrationService {
  AttendanceWorkerService({
    required Iterable<Student> students,
    FirebaseAuth? auth,
    http.Client? client,
    String? endpoint,
    StudentQrService? qrService,
    Future<String?> Function()? tokenProvider,
  }) : _students = {for (final student in students) student.studentId: student},
       _auth = auth ?? (tokenProvider == null ? FirebaseAuth.instance : null),
       _client = client ?? http.Client(),
       _endpoint = (endpoint ?? _configuredEndpoint).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _qrService = qrService ?? SecureStudentQrService(),
       _tokenProvider = tokenProvider;

  static const _configuredEndpoint = String.fromEnvironment(
    'ATTENDANCE_WORKER_URL',
    defaultValue: AttendiqoServiceEndpoints.workerBaseUrl,
  );

  final Map<String, Student> _students;
  final FirebaseAuth? _auth;
  final http.Client _client;
  final String _endpoint;
  final StudentQrService _qrService;
  final Future<String?> Function()? _tokenProvider;

  @override
  Future<QrGenerationResult> regenerate({
    required Student student,
    required UserProfile actor,
  }) async {
    final value = await _post('/v1/qr/regenerate', {
      'studentId': student.studentId,
    });
    final payload = value['payload'];
    final credential = _credential(value['credential']);
    if (payload is! String || credential == null) {
      throw const Failure(
        'The QR service returned an invalid response.',
        code: 'invalid-response',
      );
    }
    return QrGenerationResult(payload: payload, credential: credential);
  }

  @override
  Future<StudentQrCredential> setEnabled({
    required Student student,
    required bool enabled,
    required UserProfile actor,
  }) async {
    final value = await _post('/v1/qr/enabled', {
      'studentId': student.studentId,
      'enabled': enabled,
    });
    final credential = _credential(value['credential']);
    if (credential == null) {
      throw const Failure(
        'The QR service returned an invalid response.',
        code: 'invalid-response',
      );
    }
    return credential;
  }

  @override
  Future<AttendanceSession> startSession({
    required AcademicClass academicClass,
    required EffectiveClassSchedule schedule,
    required UserProfile actor,
    required DateTime date,
    required int totalStudents,
  }) async {
    final payload = <String, Object>{
      'classId': academicClass.classId,
      'date': date.toUtc().toIso8601String().split('T').first,
    };
    if (schedule.scheduleChangeId != null) {
      payload['scheduleChangeId'] = schedule.scheduleChangeId!;
    }
    return _requiredSession(
      await _post('/v1/attendance/sessions/start', payload),
    );
  }

  @override
  Future<AttendanceScanResult> recordScan(
    AttendanceScanRequest request,
  ) async {
    final tokenHash = _qrService.tokenHashFromPayload(request.payload);
    if (tokenHash.isEmpty) {
      return const AttendanceScanResult(
        ScannerResultStatus.invalidQr,
        'This QR code is invalid.',
      );
    }
    try {
      final value = await _post('/v1/attendance/scans', {
        'sessionId': request.session.sessionId,
        'tokenHash': tokenHash,
        'mode': request.mode.name,
        'deviceId': request.deviceId,
      });
      final record = _record(value['record']);
      final studentId = value['studentId'];
      if (record == null || studentId is! String) {
        throw const Failure(
          'Attendance could not be confirmed.',
          code: 'invalid-response',
        );
      }
      return AttendanceScanResult(
        ScannerResultStatus.accepted,
        value['message'] is String
            ? value['message']! as String
            : 'Attendance recorded.',
        student: _students[studentId],
        record: record,
        confirmed: true,
      );
    } on _WorkerFailure catch (failure) {
      return AttendanceScanResult(
        _scanStatus(failure.code ?? 'failure'),
        failure.message,
      );
    }
  }

  @override
  Future<AttendanceSession> closeSession(
    AttendanceSession session,
    UserProfile actor,
  ) async => _requiredSession(
    await _post('/v1/attendance/sessions/close', {
      'sessionId': session.sessionId,
    }),
  );

  @override
  Future<AttendanceSession> cancelSession(
    AttendanceSession session,
    UserProfile actor,
  ) async => _requiredSession(
    await _post('/v1/attendance/sessions/cancel', {
      'sessionId': session.sessionId,
    }),
  );

  @override
  Future<AttendanceRecord> recordManual({
    required AttendanceSession session,
    required Student student,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
  }) async => _requiredRecord(
    await _post('/v1/attendance/manual', {
      'sessionId': session.sessionId,
      'studentId': student.studentId,
      'status': status.name,
      'reason': reason.trim(),
    }),
  );

  @override
  Future<AttendanceRecord> correctRecord({
    required AttendanceRecord record,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
    DateTime? entryTime,
    DateTime? departureTime,
  }) async => _requiredRecord(
    await _post('/v1/attendance/correct', {
      'attendanceRecordId': record.attendanceRecordId,
      'status': status.name,
      'reason': reason.trim(),
      if (entryTime != null) 'entryTime': entryTime.toUtc().toIso8601String(),
      if (departureTime != null)
        'departureTime': departureTime.toUtc().toIso8601String(),
    }),
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object> payload,
  ) async {
    if (_endpoint.isEmpty) {
      throw const Failure(
        'Attendance services are not configured for this build.',
        code: 'backend-unavailable',
      );
    }
    final user = _auth?.currentUser;
    if (user == null && _tokenProvider == null) {
      throw const Failure('Sign in to use attendance.', code: 'unauthenticated');
    }
    try {
      final token = await (_tokenProvider?.call() ?? user!.getIdToken());
      if (token == null || token.isEmpty) {
        throw const Failure(
          'Your session could not be verified.',
          code: 'unauthenticated',
        );
      }
      final response = await _client
          .post(
            Uri.parse('$_endpoint$path'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _WorkerFailure(
          decoded['error'] is String ? decoded['error']! as String : 'failure',
          decoded['message'] is String
              ? decoded['message']! as String
              : 'Attendance could not be completed.',
        );
      }
      return decoded;
    } on _WorkerFailure {
      rethrow;
    } on Failure {
      rethrow;
    } catch (_) {
      throw const Failure(
        'Attendance services are temporarily unavailable.',
        code: 'backend-unavailable',
      );
    }
  }

  AttendanceSession _requiredSession(Map<String, dynamic> value) {
    final result = _session(value['session']);
    if (result == null) {
      throw const Failure(
        'The attendance service returned an invalid session.',
        code: 'invalid-response',
      );
    }
    return result;
  }

  AttendanceRecord _requiredRecord(Map<String, dynamic> value) {
    final result = _record(value['record']);
    if (result == null) {
      throw const Failure(
        'The attendance service returned an invalid record.',
        code: 'invalid-response',
      );
    }
    return result;
  }

  StudentQrCredential? _credential(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final createdAt = DateTime.tryParse(raw['createdAt'] as String? ?? '');
    if (raw['studentId'] is! String ||
        raw['instituteId'] is! String ||
        raw['tokenHash'] is! String ||
        raw['version'] is! int ||
        raw['enabled'] is! bool ||
        createdAt == null) {
      return null;
    }
    return StudentQrCredential(
      studentId: raw['studentId']! as String,
      instituteId: raw['instituteId']! as String,
      tokenHash: raw['tokenHash']! as String,
      version: raw['version']! as int,
      enabled: raw['enabled']! as bool,
      createdAt: createdAt.toUtc(),
    );
  }

  AttendanceSession? _session(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final date = _date(raw['date']);
    final startedAt = _date(raw['startedAt']);
    final createdAt = _date(raw['createdAt']);
    final updatedAt = _date(raw['updatedAt']);
    final closedAt = raw['closedAt'] == null ? null : _date(raw['closedAt']);
    final sessionType = _enum(AttendanceScanMode.values, raw['sessionType']);
    final status = _enum(AttendanceSessionStatus.values, raw['status']);
    final expectedStart = LocalTime.tryParse(raw['expectedStartTime']);
    final expectedEnd = LocalTime.tryParse(raw['expectedEndTime']);
    final effectiveStart = LocalTime.tryParse(raw['effectiveStartTime']);
    final effectiveEnd = LocalTime.tryParse(raw['effectiveEndTime']);
    if (raw['sessionId'] is! String ||
        raw['instituteId'] is! String ||
        raw['classId'] is! String ||
        date == null ||
        sessionType == null ||
        status == null ||
        startedAt == null ||
        raw['startedBy'] is! String ||
        (raw['closedAt'] != null && closedAt == null) ||
        (raw['closedBy'] != null && raw['closedBy'] is! String) ||
        expectedStart == null ||
        expectedEnd == null ||
        effectiveStart == null ||
        effectiveEnd == null ||
        raw['entryModeEnabled'] is! bool ||
        raw['departureModeEnabled'] is! bool ||
        raw['totalStudents'] is! int ||
        raw['presentCount'] is! int ||
        raw['lateCount'] is! int ||
        raw['absentCount'] is! int ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AttendanceSession(
      sessionId: raw['sessionId']! as String,
      instituteId: raw['instituteId']! as String,
      classId: raw['classId']! as String,
      date: date,
      sessionType: sessionType,
      status: status,
      startedAt: startedAt,
      startedBy: raw['startedBy']! as String,
      closedAt: closedAt,
      closedBy: raw['closedBy'] as String?,
      expectedStartTime: expectedStart,
      expectedEndTime: expectedEnd,
      effectiveStartTime: effectiveStart,
      effectiveEndTime: effectiveEnd,
      scheduleChangeId: raw['scheduleChangeId'] as String?,
      entryModeEnabled: raw['entryModeEnabled']! as bool,
      departureModeEnabled: raw['departureModeEnabled']! as bool,
      totalStudents: raw['totalStudents']! as int,
      presentCount: raw['presentCount']! as int,
      lateCount: raw['lateCount']! as int,
      absentCount: raw['absentCount']! as int,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  AttendanceRecord? _record(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final date = _date(raw['attendanceDate']);
    final entry = raw['entryTime'] == null ? null : _date(raw['entryTime']);
    final departure = raw['departureTime'] == null
        ? null
        : _date(raw['departureTime']);
    final correctedAt = raw['correctedAt'] == null
        ? null
        : _date(raw['correctedAt']);
    final createdAt = _date(raw['createdAt']);
    final updatedAt = _date(raw['updatedAt']);
    final status = _enum(AttendanceStatus.values, raw['status']);
    final method = _enum(ScanMethod.values, raw['scanMethod']);
    final sync = _enum(AttendanceSyncState.values, raw['syncState']);
    if (raw['attendanceRecordId'] is! String ||
        raw['sessionId'] is! String ||
        raw['instituteId'] is! String ||
        raw['classId'] is! String ||
        raw['studentId'] is! String ||
        date == null ||
        status == null ||
        raw['lateMinutes'] is! int ||
        method == null ||
        raw['manuallyCorrected'] is! bool ||
        sync == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AttendanceRecord(
      attendanceRecordId: raw['attendanceRecordId']! as String,
      sessionId: raw['sessionId']! as String,
      instituteId: raw['instituteId']! as String,
      classId: raw['classId']! as String,
      studentId: raw['studentId']! as String,
      attendanceDate: date,
      entryTime: entry,
      departureTime: departure,
      status: status,
      lateMinutes: raw['lateMinutes']! as int,
      entryMarkedBy: raw['entryMarkedBy'] as String?,
      departureMarkedBy: raw['departureMarkedBy'] as String?,
      entryDeviceId: raw['entryDeviceId'] as String?,
      departureDeviceId: raw['departureDeviceId'] as String?,
      scanMethod: method,
      manuallyCorrected: raw['manuallyCorrected']! as bool,
      correctionReason: raw['correctionReason'] as String?,
      correctedBy: raw['correctedBy'] as String?,
      correctedAt: correctedAt,
      syncState: sync,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  DateTime? _date(Object? value) => value is String
      ? DateTime.tryParse(value)?.toUtc()
      : null;

  T? _enum<T extends Enum>(Iterable<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  ScannerResultStatus _scanStatus(String code) => switch (code) {
    'invalid_qr' => ScannerResultStatus.invalidQr,
    'disabled_qr' => ScannerResultStatus.disabledQr,
    'wrong_institute' => ScannerResultStatus.wrongInstitute,
    'wrong_class' => ScannerResultStatus.wrongClass,
    'inactive_student' => ScannerResultStatus.inactiveStudent,
    'closed_session' => ScannerResultStatus.closedSession,
    'duplicate_entry' => ScannerResultStatus.duplicateEntry,
    'departure_before_entry' => ScannerResultStatus.departureBeforeEntry,
    'duplicate_departure' => ScannerResultStatus.duplicateDeparture,
    'forbidden' || 'cross_institute' => ScannerResultStatus.permissionDenied,
    _ => ScannerResultStatus.failure,
  };
}

class _WorkerFailure extends Failure implements Exception {
  const _WorkerFailure(String code, super.message) : super(code: code);
}
