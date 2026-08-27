import 'package:attendiqo_shared/attendiqo_shared.dart';

enum ParentDataStatus { loading, ready, empty, unavailable, error }

class ParentDataState<T> {
  const ParentDataState._(this.status, {this.data, this.message});
  const ParentDataState.loading() : this._(ParentDataStatus.loading);
  const ParentDataState.ready(T value)
    : this._(ParentDataStatus.ready, data: value);
  const ParentDataState.empty([String? message])
    : this._(ParentDataStatus.empty, message: message);
  const ParentDataState.unavailable(String message)
    : this._(ParentDataStatus.unavailable, message: message);
  const ParentDataState.error(String message)
    : this._(ParentDataStatus.error, message: message);

  final ParentDataStatus status;
  final T? data;
  final String? message;
}

enum ParentDataFailureKind {
  unauthenticated,
  permissionDenied,
  network,
  unavailable,
  malformed,
  unlinked,
  suspended,
}

class ParentDataException implements Exception {
  const ParentDataException(this.kind, this.safeMessage);
  final ParentDataFailureKind kind;
  final String safeMessage;
}

class LinkedChildRecord {
  const LinkedChildRecord({required this.link, this.profile});
  final ParentStudentLink link;
  final ParentStudentProfile? profile;

  bool get projectionMissing => profile == null;
  bool get isSelectable =>
      profile != null &&
      profile!.active &&
      profile!.instituteId == link.instituteId &&
      link.active;
  String get displayName =>
      profile?.fullName ?? 'Child information unavailable';
}

class ProjectedClassRecord {
  const ProjectedClassRecord({required this.classId, this.profile});
  final String classId;
  final ParentClassProfile? profile;
  bool get projectionMissing => profile == null;
}

class AttendanceFilters {
  const AttendanceFilters({
    this.from,
    this.to,
    this.status,
    this.classId,
    this.limit = 100,
  });
  final DateTime? from;
  final DateTime? to;
  final String? status;
  final String? classId;
  final int limit;

  AttendanceFilters copyWith({
    DateTime? from,
    DateTime? to,
    String? status,
    String? classId,
    bool clearStatus = false,
    bool clearClass = false,
  }) => AttendanceFilters(
    from: from ?? this.from,
    to: to ?? this.to,
    status: clearStatus ? null : (status ?? this.status),
    classId: clearClass ? null : (classId ?? this.classId),
    limit: limit,
  );
}

class AttendanceComputedSummary {
  const AttendanceComputedSummary({
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
    required this.total,
    required this.from,
    required this.to,
  });
  final int present;
  final int absent;
  final int late;
  final int excused;
  final int total;
  final DateTime from;
  final DateTime to;
  double get percentage => total == 0 ? 0 : (present + late) * 100 / total;
}
