import 'package:attendiqo/features/attendance/application/attendance_management_controller.dart';
import 'package:attendiqo/features/attendance/presentation/attendance_screens.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 8, 5);
  late SecureStudentQrService qr;
  late QrGenerationResult generated;
  late Student student;
  late AcademicClass academicClass;
  late UserProfile teacher;
  late MockAttendanceService service;
  late AttendanceManagementController controller;

  setUp(() {
    qr = SecureStudentQrService();
    generated = qr.generate(
      studentId: 'student-a',
      instituteId: 'institute-a',
      version: 1,
      now: now,
    );
    student = Student(
      studentId: 'student-a',
      instituteId: 'institute-a',
      studentNumber: 'STU-A',
      fullName: 'Student A',
      primaryParentName: 'Parent',
      primaryParentMobile: '+94771234567',
      status: StudentStatus.active,
      qrToken: generated.credential.tokenHash,
      createdAt: now,
      createdBy: 'admin-a',
      updatedAt: now,
    );
    academicClass = AcademicClass.newClass(
      classId: 'class-a',
      instituteId: 'institute-a',
      classCode: 'CLASS-A',
      name: 'English',
      subject: 'English',
      teacherIds: const ['teacher-a'],
      primaryTeacherId: 'teacher-a',
      daysOfWeek: const {ClassWeekday.monday},
      startTime: const LocalTime(8, 0),
      endTime: const LocalTime(9, 0),
      academicYear: 2026,
      now: now,
      actorUid: 'admin-a',
    );
    teacher = UserProfile.newTeacher(
      uid: 'teacher-a',
      email: 'teacher@example.com',
      displayName: 'Teacher',
      instituteId: 'institute-a',
      createdBy: 'admin-a',
      now: now,
      permissions: const TeacherPermissions(canCorrectAttendance: true),
    );
    final assignment = ClassStudentAssignment(
      assignmentId: 'class-a_student-a',
      instituteId: 'institute-a',
      classId: 'class-a',
      studentId: 'student-a',
      active: true,
      joinedAt: now,
      joinedBy: 'admin-a',
      status: ClassStudentAssignmentStatus.active,
      scheduleOverlapConfirmed: false,
    );
    service = MockAttendanceService(
      qrService: qr,
      students: {'student-a': student},
      credentials: {generated.credential.tokenHash: generated.credential},
      assignments: [assignment],
      classes: {'class-a': academicClass},
      clock: () => now,
    );
    controller = AttendanceManagementController(
      actor: teacher,
      classes: [academicClass],
      students: [student],
      assignments: [assignment],
      scheduleChanges: const [],
      service: service,
      qrAdministrationService: MockQrAdministrationService(qrService: qr),
    );
    controller.selectClass(academicClass);
  });

  tearDown(() => controller.dispose());

  test(
    'successful scan stays active, requires no confirmation, and updates latest student',
    () async {
      expect(await controller.startSession(DateTime.utc(2026, 8, 3)), isTrue);
      final result = await controller.processPayload(generated.payload);
      expect(result.accepted, isTrue);
      expect(controller.scannerActive, isTrue);
      expect(controller.latest?.student?.fullName, 'Student A');
      expect(controller.scannedCount, 1);
    },
  );

  test('offline result never reports cloud confirmation', () async {
    await controller.startSession(DateTime.utc(2026, 8, 3));
    controller.setOnline(false);
    final result = await controller.processPayload(generated.payload);
    expect(result.status, ScannerResultStatus.networkError);
    expect(result.confirmed, isFalse);
    expect(controller.records, isEmpty);
  });

  testWidgets(
    'scanner shows required live context and latest result without a photo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.startSession(DateTime.utc(2026, 8, 3));
      await tester.pumpWidget(
        MaterialApp(
          home: ContinuousScannerScreen(
            controller: controller,
            cameraPreview: const ColoredBox(
              color: Colors.black,
              child: Center(child: Text('Camera preview')),
            ),
          ),
        ),
      );
      expect(find.text('Camera preview'), findsOneWidget);
      expect(find.text('Entry'), findsOneWidget);
      expect(find.text('Scanned'), findsOneWidget);
      await controller.processPayload(generated.payload);
      await tester.pump();
      expect(find.textContaining('Student A'), findsOneWidget);
      expect(
        find.textContaining('No per-student confirmation'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
    },
  );

  test(
    'QR card PDF contains a valid PDF document and no parent mobile bytes',
    () async {
      final bytes = await QrPdfExporter.buildSingle(
        student: student,
        payload: generated.payload,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(
        String.fromCharCodes(bytes),
        isNot(contains(student.primaryParentMobile)),
      );
    },
  );
}
