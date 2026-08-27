import 'dart:async';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

import '../data/parent_projection_repository.dart';
import '../domain/parent_data.dart';

class ParentDataController extends ChangeNotifier {
  factory ParentDataController({
    required ParentProjectionRepository repository,
    required UserProfile parentProfile,
  }) => ParentDataController._(repository, parentProfile);

  ParentDataController._(this._repository, this.parentProfile);

  final ParentProjectionRepository _repository;
  final UserProfile parentProfile;
  StreamSubscription<List<ParentStudentLink>>? _linksSubscription;
  StreamSubscription<List<LinkedChildRecord>>? _childrenSubscription;
  StreamSubscription<List<ProjectedClassRecord>>? _classesSubscription;
  StreamSubscription<List<ParentAttendanceSummary>>?
  _todayAttendanceSubscription;
  StreamSubscription<List<ParentAttendanceSummary>>? _attendanceSubscription;
  StreamSubscription<List<ParentNotice>>? _noticesSubscription;
  StreamSubscription<InstitutePublicProfile?>? _instituteSubscription;
  var _generation = 0;
  var _disposed = false;

  ParentDataState<List<ParentStudentLink>> links =
      const ParentDataState.loading();
  ParentDataState<List<LinkedChildRecord>> children =
      const ParentDataState.loading();
  ParentDataState<ParentStudentProfile> childProfile =
      const ParentDataState.loading();
  ParentDataState<List<ProjectedClassRecord>> classes =
      const ParentDataState.loading();
  ParentDataState<List<ParentAttendanceSummary>> attendanceToday =
      const ParentDataState.loading();
  ParentDataState<List<ParentAttendanceSummary>> attendance =
      const ParentDataState.loading();
  ParentDataState<List<ParentNotice>> notices = const ParentDataState.loading();
  ParentDataState<InstitutePublicProfile> institute =
      const ParentDataState.loading();
  LinkedChildRecord? selectedChild;
  AttendanceFilters attendanceFilters = AttendanceFilters(
    from: DateTime.now().subtract(const Duration(days: 30)),
    to: DateTime.now(),
  );

  void start() => _watchLinks();

  void _watchLinks() {
    _linksSubscription?.cancel();
    links = const ParentDataState.loading();
    if (!_disposed) notifyListeners();
    try {
      _linksSubscription = _repository.watchOwnActiveLinks().listen(
        _onLinks,
        onError: (Object error) {
          links = _stateForError<List<ParentStudentLink>>(error);
          children = _stateForError<List<LinkedChildRecord>>(error);
          _clearSelectedChild();
          _notify();
        },
      );
    } catch (error) {
      links = _stateForError<List<ParentStudentLink>>(error);
      children = _stateForError<List<LinkedChildRecord>>(error);
      _clearSelectedChild();
      _notify();
    }
  }

  void _onLinks(List<ParentStudentLink> values) {
    final safeLinks = values.where((link) => link.active).toList();
    links = safeLinks.isEmpty
        ? const ParentDataState.empty('No children are linked to this account.')
        : ParentDataState.ready(List.unmodifiable(safeLinks));
    _childrenSubscription?.cancel();
    if (safeLinks.isEmpty) {
      children = const ParentDataState.empty(
        'No children are linked to this account.',
      );
      _clearSelectedChild();
      _notify();
      return;
    }
    children = const ParentDataState.loading();
    _clearSelectedChildIfUnlinked(safeLinks);
    _notify();
    try {
      _childrenSubscription = _repository
          .watchLinkedChildren(safeLinks)
          .listen(
            _onChildren,
            onError: (Object error) {
              children = _stateForError<List<LinkedChildRecord>>(error);
              _clearSelectedChild();
              _notify();
            },
          );
    } catch (error) {
      children = _stateForError<List<LinkedChildRecord>>(error);
      _clearSelectedChild();
      _notify();
    }
  }

  void _onChildren(List<LinkedChildRecord> values) {
    children = values.isEmpty
        ? const ParentDataState.empty('No children are linked to this account.')
        : ParentDataState.ready(List.unmodifiable(values));
    final selectable = values.where((child) => child.isSelectable).toList();
    final selectedId = selectedChild?.link.studentId;
    final replacement = selectable
        .where((child) => child.link.studentId == selectedId)
        .firstOrNull;
    if (replacement != null) {
      final previous = selectedChild;
      selectedChild = replacement;
      childProfile = ParentDataState.ready(replacement.profile!);
      final scopeChanged =
          previous?.profile?.sourceVersion !=
              replacement.profile?.sourceVersion ||
          previous?.link.instituteId != replacement.link.instituteId;
      if (scopeChanged) {
        _generation++;
        final generation = _generation;
        _cancelChildSubscriptions();
        classes = const ParentDataState.loading();
        attendanceToday = const ParentDataState.loading();
        attendance = const ParentDataState.loading();
        notices = const ParentDataState.loading();
        institute = const ParentDataState.loading();
        _subscribeForChild(replacement, generation);
      }
      _notify();
      return;
    }
    if (selectable.isEmpty) {
      _clearSelectedChild();
      childProfile = const ParentDataState.unavailable(
        'Linked child information has not been prepared yet.',
      );
      _notify();
      return;
    }
    selectChild(selectable.first.link.studentId);
  }

  bool selectChild(String studentId) {
    final available = children.data ?? const <LinkedChildRecord>[];
    final matches = available.where(
      (child) => child.link.studentId == studentId && child.isSelectable,
    );
    if (matches.isEmpty) return false;
    final child = matches.first;
    if (selectedChild?.link.studentId == child.link.studentId &&
        selectedChild?.link.instituteId == child.link.instituteId) {
      return true;
    }
    _generation++;
    final generation = _generation;
    _cancelChildSubscriptions();
    selectedChild = child;
    childProfile = ParentDataState.ready(child.profile!);
    classes = const ParentDataState.loading();
    attendanceToday = const ParentDataState.loading();
    attendance = const ParentDataState.loading();
    notices = const ParentDataState.loading();
    institute = const ParentDataState.loading();
    _notify();
    _subscribeForChild(child, generation);
    return true;
  }

  void _subscribeForChild(LinkedChildRecord child, int generation) {
    try {
      _classesSubscription = _repository
          .watchChildClasses(child)
          .listen(
            (values) {
              if (!_current(generation)) return;
              if (values.isEmpty) {
                classes = const ParentDataState.empty(
                  'No classes are available for this child.',
                );
              } else if (values.every((item) => item.projectionMissing)) {
                classes = const ParentDataState.unavailable(
                  'Class information has not been prepared yet.',
                );
              } else {
                classes = ParentDataState.ready(List.unmodifiable(values));
              }
              _notify();
            },
            onError: (Object error) {
              if (_current(generation)) {
                classes = _stateForError<List<ProjectedClassRecord>>(error);
                _notify();
              }
            },
          );
      _watchTodayAttendance(child, generation);
      _watchAttendance(child, generation);
      _noticesSubscription = _repository
          .watchApplicableNotices(child)
          .listen(
            (values) {
              if (!_current(generation)) return;
              notices = values.isEmpty
                  ? const ParentDataState.empty('No notices are available.')
                  : ParentDataState.ready(List.unmodifiable(values));
              _notify();
            },
            onError: (Object error) {
              if (_current(generation)) {
                notices = _stateForError<List<ParentNotice>>(error);
                _notify();
              }
            },
          );
      _instituteSubscription = _repository
          .watchLinkedInstituteProfile(
            child.link.instituteId,
            links.data ?? const [],
          )
          .listen(
            (value) {
              if (!_current(generation)) return;
              if (value == null) {
                institute = const ParentDataState.unavailable(
                  'Institute information has not been prepared yet.',
                );
              } else if (value.status != 'active') {
                institute = const ParentDataState.unavailable(
                  'Institute information is unavailable while the institute is suspended.',
                );
              } else {
                institute = ParentDataState.ready(value);
              }
              _notify();
            },
            onError: (Object error) {
              if (_current(generation)) {
                institute = _stateForError<InstitutePublicProfile>(error);
                _notify();
              }
            },
          );
    } catch (error) {
      if (_current(generation)) {
        final state = _stateForError<Object>(error);
        classes = ParentDataState.error(
          state.message ?? 'Class information failed to load.',
        );
        attendanceToday = ParentDataState.error(
          state.message ?? 'Today\'s attendance failed to load.',
        );
        attendance = ParentDataState.error(
          state.message ?? 'Attendance failed to load.',
        );
        notices = ParentDataState.error(
          state.message ?? 'Notices failed to load.',
        );
        institute = ParentDataState.error(
          state.message ?? 'Institute information failed to load.',
        );
        _notify();
      }
    }
  }

  void _watchAttendance(LinkedChildRecord child, int generation) {
    _attendanceSubscription?.cancel();
    attendance = const ParentDataState.loading();
    _attendanceSubscription = _repository
        .watchChildAttendance(child, attendanceFilters)
        .listen(
          (values) {
            if (!_current(generation)) return;
            attendance = values.isEmpty
                ? const ParentDataState.empty(
                    'No attendance records exist for this date range.',
                  )
                : ParentDataState.ready(List.unmodifiable(values));
            _notify();
          },
          onError: (Object error) {
            if (_current(generation)) {
              attendance = _stateForError<List<ParentAttendanceSummary>>(error);
              _notify();
            }
          },
        );
  }

  void _watchTodayAttendance(LinkedChildRecord child, int generation) {
    _todayAttendanceSubscription?.cancel();
    attendanceToday = const ParentDataState.loading();
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    _todayAttendanceSubscription = _repository
        .watchChildAttendance(
          child,
          AttendanceFilters(from: from, to: to, limit: 30),
        )
        .listen(
          (values) {
            if (!_current(generation)) return;
            attendanceToday = values.isEmpty
                ? const ParentDataState.empty(
                    'No attendance records exist for today.',
                  )
                : ParentDataState.ready(List.unmodifiable(values));
            _notify();
          },
          onError: (Object error) {
            if (_current(generation)) {
              attendanceToday = _stateForError<List<ParentAttendanceSummary>>(
                error,
              );
              _notify();
            }
          },
        );
  }

  void updateAttendanceFilters(AttendanceFilters filters) {
    attendanceFilters = filters;
    final child = selectedChild;
    if (child == null) return;
    final generation = _generation;
    _watchAttendance(child, generation);
    _notify();
  }

  List<ParentAttendanceSummary> get todayAttendance {
    final now = DateTime.now();
    return (attendanceToday.data ?? const [])
        .where(
          (record) =>
              record.attendanceDate.year == now.year &&
              record.attendanceDate.month == now.month &&
              record.attendanceDate.day == now.day,
        )
        .toList();
  }

  AttendanceComputedSummary? get computedSummary {
    final records = attendance.data;
    if (records == null || records.isEmpty) return null;
    return AttendanceComputedSummary(
      present: records.where((item) => item.status == 'present').length,
      absent: records.where((item) => item.status == 'absent').length,
      late: records.where((item) => item.status == 'late').length,
      excused: records.where((item) => item.status == 'excused').length,
      total: records.length,
      from: attendanceFilters.from ?? records.last.attendanceDate,
      to: attendanceFilters.to ?? records.first.attendanceDate,
    );
  }

  String className(String classId) {
    for (final record in classes.data ?? const <ProjectedClassRecord>[]) {
      if (record.classId == classId) {
        return record.profile?.className ?? 'Class information unavailable';
      }
    }
    return 'Class information unavailable';
  }

  void retryLinks() => _watchLinks();
  void retrySelectedChild() {
    final child = selectedChild;
    if (child != null) {
      _generation++;
      final generation = _generation;
      _cancelChildSubscriptions();
      classes = const ParentDataState.loading();
      attendanceToday = const ParentDataState.loading();
      attendance = const ParentDataState.loading();
      notices = const ParentDataState.loading();
      institute = const ParentDataState.loading();
      _notify();
      _subscribeForChild(child, generation);
    }
  }

  void clearSession() {
    _generation++;
    _linksSubscription?.cancel();
    _childrenSubscription?.cancel();
    _cancelChildSubscriptions();
    selectedChild = null;
    links = const ParentDataState.empty();
    children = const ParentDataState.empty();
    childProfile = const ParentDataState.empty();
    classes = const ParentDataState.empty();
    attendanceToday = const ParentDataState.empty();
    attendance = const ParentDataState.empty();
    notices = const ParentDataState.empty();
    institute = const ParentDataState.empty();
    _notify();
  }

  void _clearSelectedChildIfUnlinked(List<ParentStudentLink> activeLinks) {
    final selected = selectedChild;
    if (selected != null &&
        !activeLinks.any(
          (link) =>
              link.studentId == selected.link.studentId &&
              link.instituteId == selected.link.instituteId,
        )) {
      _clearSelectedChild();
    }
  }

  void _clearSelectedChild() {
    _generation++;
    _cancelChildSubscriptions();
    selectedChild = null;
    childProfile = const ParentDataState.empty();
    classes = const ParentDataState.empty();
    attendanceToday = const ParentDataState.empty();
    attendance = const ParentDataState.empty();
    notices = const ParentDataState.empty();
    institute = const ParentDataState.empty();
  }

  void _cancelChildSubscriptions() {
    _classesSubscription?.cancel();
    _todayAttendanceSubscription?.cancel();
    _attendanceSubscription?.cancel();
    _noticesSubscription?.cancel();
    _instituteSubscription?.cancel();
    _classesSubscription = null;
    _todayAttendanceSubscription = null;
    _attendanceSubscription = null;
    _noticesSubscription = null;
    _instituteSubscription = null;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  ParentDataState<T> _stateForError<T>(Object error) {
    final safe = error is ParentDataException
        ? error
        : const ParentDataException(
            ParentDataFailureKind.unavailable,
            'Parent information is temporarily unavailable.',
          );
    return switch (safe.kind) {
      ParentDataFailureKind.unavailable || ParentDataFailureKind.suspended =>
        ParentDataState<T>.unavailable(safe.safeMessage),
      _ => ParentDataState<T>.error(safe.safeMessage),
    };
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _linksSubscription?.cancel();
    _childrenSubscription?.cancel();
    _cancelChildSubscriptions();
    super.dispose();
  }
}
