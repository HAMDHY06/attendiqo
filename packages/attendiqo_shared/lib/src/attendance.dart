import 'contracts.dart';
import 'models.dart';

class DuplicateScanGuard {
  DuplicateScanGuard({this.cooldown = const Duration(seconds: 3)});
  final Duration cooldown;
  final Map<String, DateTime> _lastSeen = {};
  bool accept(String token, DateTime now) {
    final previous = _lastSeen[token];
    if (previous != null && now.difference(previous) < cooldown) return false;
    _lastSeen[token] = now;
    return true;
  }
}

class AttendanceCoordinator {
  const AttendanceCoordinator({
    required this.attendanceRepository,
    required this.notificationService,
    required this.smsService,
  });
  final AttendanceRepository attendanceRepository;
  final NotificationService notificationService;
  final SmsService smsService;

  Future<Result<AttendanceRecord>> save(AttendanceRecord record) async {
    final result = await attendanceRepository.save(record);
    // Delivery is deliberately handled after persistence by a future trusted
    // backend. Notification or SMS failure must never roll back attendance.
    return result;
  }
}
