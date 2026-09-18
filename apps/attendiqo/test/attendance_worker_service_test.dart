import 'dart:convert';

import 'package:attendiqo/services/attendance_worker_service.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 3);
  final student = Student(
    studentId: 'student-a',
    instituteId: 'institute-a',
    studentNumber: 'ST-001',
    fullName: 'Student A',
    address: '',
    primaryParentName: 'Parent A',
    primaryParentMobile: '0771234567',
    status: StudentStatus.active,
    qrToken: 'a' * 64,
    createdAt: now,
    createdBy: 'admin-a',
    updatedAt: now,
  );

  AttendanceWorkerService service(
    http.Response Function(http.Request) handler,
  ) => AttendanceWorkerService(
    students: [student],
    endpoint: 'https://worker.example',
    tokenProvider: () async => 'firebase-token',
    client: MockClient((request) async => handler(request)),
  );

  test('parses a one-time QR response without exposing auth in its body', () async {
    late http.Request sent;
    final client = service((request) {
      sent = request;
      return http.Response(
        jsonEncode({
          'payload': 'attendiqo://student/${'b' * 43}',
          'credential': {
            'studentId': 'student-a',
            'instituteId': 'institute-a',
            'tokenHash': 'c' * 64,
            'version': 2,
            'enabled': true,
            'createdAt': now.toIso8601String(),
          },
        }),
        200,
      );
    });
    final result = await client.regenerate(student: student, actor: _actor(now));
    expect(result.credential.version, 2);
    expect(sent.headers['authorization'], 'Bearer firebase-token');
    expect(sent.body, isNot(contains('firebase-token')));
  });

  test('maps trusted scan rejections to scanner feedback', () async {
    final client = service(
      (_) => http.Response(
        jsonEncode({
          'error': 'duplicate_entry',
          'message': 'Entry is already recorded.',
        }),
        409,
      ),
    );
    final result = await client.recordScan(
      AttendanceScanRequest(
        payload: 'attendiqo://student/${'b' * 43}',
        session: _session(now),
        mode: AttendanceScanMode.entry,
        actor: _actor(now),
        deviceId: 'device-a',
      ),
    );
    expect(result.status, ScannerResultStatus.duplicateEntry);
    expect(result.confirmed, isFalse);
  });
}

UserProfile _actor(DateTime now) => UserProfile(
  uid: 'admin-a',
  email: 'admin@example.com',
  displayName: 'Admin',
  role: UserRole.instituteAdmin,
  instituteId: 'institute-a',
  active: true,
  mustChangePassword: false,
  createdAt: now,
  createdBy: 'system',
  updatedAt: now,
);

AttendanceSession _session(DateTime now) => AttendanceSession(
  sessionId: 'd' * 64,
  instituteId: 'institute-a',
  classId: 'class-a',
  date: DateTime.utc(2026, 9, 3),
  sessionType: AttendanceScanMode.entry,
  status: AttendanceSessionStatus.open,
  startedAt: now,
  startedBy: 'admin-a',
  expectedStartTime: const LocalTime(8, 0),
  expectedEndTime: const LocalTime(10, 0),
  effectiveStartTime: const LocalTime(8, 0),
  effectiveEndTime: const LocalTime(10, 0),
  entryModeEnabled: true,
  departureModeEnabled: true,
  totalStudents: 1,
  presentCount: 0,
  lateCount: 0,
  absentCount: 0,
  createdAt: now,
  updatedAt: now,
);
