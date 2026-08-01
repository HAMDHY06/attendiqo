import 'enums.dart';
import 'models.dart';
import 'academic.dart';
import 'attendance_phase.dart';

abstract interface class StudentRepository {
  Future<Student?> findByQrToken(String opaqueToken);
}

abstract interface class AttendanceRepository {
  Future<Result<AttendanceRecord>> save(AttendanceRecord record);
}

abstract interface class QrService {
  Future<QrToken> generate(String studentId);
  Future<QrToken> regenerate(String studentId);
  Future<void> disable(String studentId);
  Future<bool> validate(String opaqueToken, {required String classId});
  Future<List<int>> exportPdf(String studentId);
}

abstract interface class NotificationService {
  Future<Result<void>> send(AttendanceNotification notification);
}

abstract interface class NotificationTokenRepository {
  Future<void> save(FcmToken token);
  Future<void> remove(String token);
}

abstract interface class SmsService {
  Future<Result<SmsLog>> send({
    required String attendanceEventId,
    required String instituteName,
    required String recipient,
    required String studentName,
    required String className,
    required DateTime occurredAt,
    required SmsMessageType type,
  });
}

class MockNotificationService implements NotificationService {
  final List<AttendanceNotification> sent = [];
  @override
  Future<Result<void>> send(AttendanceNotification notification) async {
    sent.add(notification);
    return const Success(null);
  }
}

class MockSmsService implements SmsService {
  final List<String> attemptedEventIds = [];
  @override
  Future<Result<SmsLog>> send({
    required String attendanceEventId,
    required String instituteName,
    required String recipient,
    required String studentName,
    required String className,
    required DateTime occurredAt,
    required SmsMessageType type,
  }) async {
    attemptedEventIds.add(attendanceEventId);
    return Success(
      SmsLog(
        id: 'mock-$attendanceEventId',
        attendanceEventId: attendanceEventId,
        type: type,
        status: SmsDeliveryStatus.skipped,
        createdAt: occurredAt,
        providerResponse: 'mock-only',
      ),
    );
  }
}
