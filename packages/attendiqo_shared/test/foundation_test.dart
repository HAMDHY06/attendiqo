import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements AttendanceRepository {
  bool saved = false;
  @override
  Future<Result<AttendanceRecord>> save(AttendanceRecord record) async {
    saved = true;
    return Success(record);
  }
}

void main() {
  test('all four roles are defined', () {
    expect(UserRole.values, [
      UserRole.superAdmin,
      UserRole.instituteAdmin,
      UserRole.teacher,
      UserRole.parent,
    ]);
  });

  test('mobile validation requires primary and permits empty secondary', () {
    expect(MobileNumberValidator.validatePrimary(''), isNotNull);
    expect(MobileNumberValidator.validatePrimary('0771234567'), isNull);
    expect(MobileNumberValidator.normalize('0771234567'), '+94771234567');
    expect(MobileNumberValidator.validateSecondary(null), isNull);
  });

  test('student model has no photograph field', () {
    final student = Student(
      studentId: 's1',
      instituteId: 'i1',
      studentNumber: '001',
      fullName: 'Test Student',
      primaryParentName: 'Parent',
      primaryParentMobile: '+94771234567',
      status: StudentStatus.active,
      qrToken: 'opaque',
      createdAt: DateTime.utc(2026),
      createdBy: 'u1',
      updatedAt: DateTime.utc(2026),
    );
    expect(student.toString(), isNot(contains('photo')));
  });

  test('SMS is disabled by default and mock remains local', () async {
    expect(const SmsConfiguration().enabled, isFalse);
    final service = MockSmsService();
    final result = await service.send(
      attendanceEventId: 'e1',
      instituteName: 'Institute',
      recipient: '+94771234567',
      studentName: 'Student',
      className: 'Class',
      occurredAt: DateTime.utc(2026),
      type: SmsMessageType.arrival,
    );
    expect(service.attemptedEventIds, ['e1']);
    expect((result as Success<SmsLog>).value.status, SmsDeliveryStatus.skipped);
  });

  test('attendance persistence is independent of delivery', () async {
    final repository = _Repository();
    final coordinator = AttendanceCoordinator(
      attendanceRepository: repository,
      notificationService: MockNotificationService(),
      smsService: MockSmsService(),
    );
    final record = AttendanceRecord(
      recordId: 'r1',
      sessionId: 'ss1',
      instituteId: 'i1',
      classId: 'c1',
      studentId: 's1',
      status: AttendanceStatus.present,
      recordedBy: 't1',
      deviceIdentifier: 'test',
    );
    expect(await coordinator.save(record), isA<Success<AttendanceRecord>>());
    expect(repository.saved, isTrue);
  });

  test('notification types include arrival and departure', () {
    expect(
      NotificationType.values,
      containsAll([NotificationType.arrival, NotificationType.departure]),
    );
    final time = DateTime.utc(2026);
    expect(
      ArrivalNotification(
        id: 'n1',
        instituteName: 'Institute',
        studentName: 'Student',
        className: 'Class',
        occurredAt: time,
      ).type,
      NotificationType.arrival,
    );
    expect(
      DepartureNotification(
        id: 'n2',
        instituteName: 'Institute',
        studentName: 'Student',
        className: 'Class',
        occurredAt: time,
      ).type,
      NotificationType.departure,
    );
  });

  test('collection constants use required snake-case names', () {
    expect(FirestoreCollections.instituteMembers, 'institute_members');
    expect(
      FirestoreCollections.notificationTemplates,
      'notification_templates',
    );
    expect(FirestoreCollections.systemSettings, 'system_settings');
  });
}
