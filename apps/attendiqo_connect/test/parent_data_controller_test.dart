import 'dart:async';

import 'package:attendiqo_connect/features/parent/application/parent_data_controller.dart';
import 'package:attendiqo_connect/features/parent/data/parent_projection_repository.dart';
import 'package:attendiqo_connect/features/parent/domain/parent_data.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParentDataController', () {
    late FakeParentProjectionRepository repository;
    late ParentDataController controller;

    setUp(() {
      repository = FakeParentProjectionRepository();
      controller = ParentDataController(
        repository: repository,
        parentProfile: _parentProfile(),
      )..start();
    });

    tearDown(() async {
      controller.dispose();
      await repository.dispose();
    });

    test('selects the first valid linked child', () async {
      final link = _link('student-a');
      repository.links.add([link]);
      await _flush();
      repository.children.add([_child(link, name: 'Child A')]);
      await _flush();

      expect(controller.selectedChild?.displayName, 'Child A');
      expect(controller.childProfile.status, ParentDataStatus.ready);
      expect(repository.classWatchCount['student-a'], 1);
    });

    test('rejects selection of an unlinked student before a read', () async {
      final link = _link('student-a');
      repository.links.add([link]);
      await _flush();
      repository.children.add([_child(link)]);
      await _flush();

      expect(controller.selectChild('student-other'), isFalse);
      expect(controller.selectedChild?.link.studentId, 'student-a');
      expect(repository.classWatchCount['student-other'], isNull);
    });

    test('clears child A data before child B subscriptions emit', () async {
      final linkA = _link('student-a');
      final linkB = _link('student-b');
      repository.links.add([linkA, linkB]);
      await _flush();
      repository.children.add([
        _child(linkA, name: 'Child A'),
        _child(linkB, name: 'Child B'),
      ]);
      await _flush();
      repository.classesFor('student-a').add([_projectedClass('class-a')]);
      repository.attendanceFor('student-a').add([
        _attendance('student-a', 'class-a'),
      ]);
      repository.noticesFor('student-a').add([_notice('notice-a')]);
      await _flush();
      expect(controller.classes.status, ParentDataStatus.ready);

      expect(controller.selectChild('student-b'), isTrue);
      expect(controller.selectedChild?.displayName, 'Child B');
      expect(controller.classes.status, ParentDataStatus.loading);
      expect(controller.attendance.status, ParentDataStatus.loading);
      expect(controller.notices.status, ParentDataStatus.loading);

      repository.classesFor('student-a').add([_projectedClass('stale-a')]);
      repository.attendanceFor('student-a').add([
        _attendance('student-a', 'stale-a'),
      ]);
      repository.noticesFor('student-a').add([_notice('stale-a')]);
      await _flush();
      expect(controller.classes.data, isNull);
      expect(controller.attendance.data, isNull);
      expect(controller.notices.data, isNull);
      expect(repository.cancelledChildren, contains('student-a'));
    });

    test('revoked link removes selected child and scoped state', () async {
      final link = _link('student-a');
      repository.links.add([link]);
      await _flush();
      repository.children.add([_child(link)]);
      await _flush();

      repository.links.add(const []);
      await _flush();

      expect(controller.selectedChild, isNull);
      expect(controller.children.status, ParentDataStatus.empty);
      expect(controller.attendance.status, ParentDataStatus.empty);
    });

    test(
      'missing projection is unavailable rather than fabricated empty data',
      () async {
        final link = _link('student-a');
        repository.links.add([link]);
        await _flush();
        repository.children.add([LinkedChildRecord(link: link)]);
        await _flush();

        expect(controller.selectedChild, isNull);
        expect(controller.childProfile.status, ParentDataStatus.unavailable);
        expect(controller.computedSummary, isNull);
      },
    );

    test('logout clears selection and every cached projection', () async {
      final link = _link('student-a');
      repository.links.add([link]);
      await _flush();
      repository.children.add([_child(link)]);
      await _flush();

      controller.clearSession();

      expect(controller.selectedChild, isNull);
      expect(controller.links.status, ParentDataStatus.empty);
      expect(controller.classes.data, isNull);
      expect(controller.attendance.data, isNull);
      expect(controller.notices.data, isNull);
    });

    test('summary uses real records and distinguishes unavailable', () async {
      final link = _link('student-a');
      repository.links.add([link]);
      await _flush();
      repository.children.add([_child(link)]);
      await _flush();
      repository.attendanceFor('student-a').add([
        _attendance('student-a', 'class-a', status: 'present'),
        _attendance('student-a', 'class-a', status: 'late'),
        _attendance('student-a', 'class-a', status: 'absent'),
      ]);
      await _flush();

      final summary = controller.computedSummary!;
      expect(summary.total, 3);
      expect(summary.present, 1);
      expect(summary.late, 1);
      expect(summary.absent, 1);
      expect(summary.percentage, closeTo(66.67, 0.01));

      repository
          .attendanceFor('student-a')
          .addError(
            const ParentDataException(
              ParentDataFailureKind.unavailable,
              'Attendance information is not available yet.',
            ),
          );
      await _flush();
      expect(controller.attendance.status, ParentDataStatus.unavailable);
      expect(controller.computedSummary, isNull);
    });
  });
}

class FakeParentProjectionRepository implements ParentProjectionRepository {
  final links = StreamController<List<ParentStudentLink>>.broadcast(sync: true);
  final children = StreamController<List<LinkedChildRecord>>.broadcast(
    sync: true,
  );
  final _classes = <String, StreamController<List<ProjectedClassRecord>>>{};
  final _attendance =
      <String, StreamController<List<ParentAttendanceSummary>>>{};
  final _notices = <String, StreamController<List<ParentNotice>>>{};
  final classWatchCount = <String, int>{};
  final cancelledChildren = <String>[];

  StreamController<List<ProjectedClassRecord>> classesFor(String studentId) =>
      _classes.putIfAbsent(
        studentId,
        () => StreamController.broadcast(sync: true),
      );
  StreamController<List<ParentAttendanceSummary>> attendanceFor(
    String studentId,
  ) => _attendance.putIfAbsent(
    studentId,
    () => StreamController.broadcast(sync: true),
  );
  StreamController<List<ParentNotice>> noticesFor(String studentId) => _notices
      .putIfAbsent(studentId, () => StreamController.broadcast(sync: true));

  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() => links.stream;

  @override
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  ) => children.stream;

  @override
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) => const Stream.empty();

  @override
  Stream<List<ProjectedClassRecord>> watchChildClasses(
    LinkedChildRecord child,
  ) {
    final studentId = child.link.studentId;
    classWatchCount.update(studentId, (value) => value + 1, ifAbsent: () => 1);
    final source = classesFor(studentId);
    late StreamController<List<ProjectedClassRecord>> scoped;
    StreamSubscription<List<ProjectedClassRecord>>? subscription;
    scoped = StreamController<List<ProjectedClassRecord>>(
      onListen: () {
        subscription = source.stream.listen(
          scoped.add,
          onError: scoped.addError,
        );
      },
      onCancel: () async {
        cancelledChildren.add(studentId);
        await subscription?.cancel();
      },
    );
    return scoped.stream;
  }

  @override
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  ) => attendanceFor(child.link.studentId).stream;

  @override
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child) =>
      noticesFor(child.link.studentId).stream;

  @override
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  ) => Stream.value(
    InstitutePublicProfile(
      instituteId: instituteId,
      displayName: 'Safe Institute',
      status: 'active',
      updatedAt: DateTime.utc(2026),
      sourceVersion: 1,
    ),
  );

  Future<void> dispose() async {
    await links.close();
    await children.close();
    for (final controller in [
      ..._classes.values,
      ..._attendance.values,
      ..._notices.values,
    ]) {
      await controller.close();
    }
  }
}

UserProfile _parentProfile() => UserProfile(
  uid: 'parent-1',
  email: 'parent@example.com',
  displayName: 'Parent',
  role: UserRole.parent,
  instituteId: null,
  active: true,
  mustChangePassword: false,
  createdAt: DateTime.utc(2026),
  createdBy: 'trusted-system',
  updatedAt: DateTime.utc(2026),
);

ParentStudentLink _link(String studentId) => ParentStudentLink(
  parentUid: 'parent-1',
  studentId: studentId,
  instituteId: 'institute-1',
  relationship: 'parent',
  active: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  createdBy: 'admin-1',
  sourceVersion: 1,
);

LinkedChildRecord _child(
  ParentStudentLink link, {
  String name = 'Linked Child',
}) => LinkedChildRecord(
  link: link,
  profile: ParentStudentProfile(
    studentId: link.studentId,
    instituteId: link.instituteId,
    fullName: name,
    studentNumber: 'ST-001',
    grade: 'Grade 8',
    active: true,
    classIds: const ['class-a'],
    updatedAt: DateTime.utc(2026),
    sourceVersion: 1,
  ),
);

ProjectedClassRecord _projectedClass(String classId) => ProjectedClassRecord(
  classId: classId,
  profile: ParentClassProfile(
    classId: classId,
    instituteId: 'institute-1',
    className: 'Mathematics',
    subject: 'Maths',
    active: true,
    updatedAt: DateTime.utc(2026),
    sourceVersion: 1,
  ),
);

ParentAttendanceSummary _attendance(
  String studentId,
  String classId, {
  String status = 'present',
}) => ParentAttendanceSummary(
  summaryId: '${studentId}_2026-01-01_$classId',
  studentId: studentId,
  instituteId: 'institute-1',
  classId: classId,
  attendanceDate: DateTime.utc(2026, 1),
  status: status,
  late: status == 'late',
  currentPresenceState: 'outside',
  updatedAt: DateTime.utc(2026, 1),
  sourceVersion: 1,
);

ParentNotice _notice(String id) => ParentNotice(
  noticeId: id,
  instituteId: 'institute-1',
  title: 'Notice',
  message: 'Safe message',
  publishedAt: DateTime.utc(2026),
  priority: ParentNoticePriority.normal,
  active: true,
  targetType: ParentNoticeTargetType.student,
  targetStudentIds: const ['student-a'],
  updatedAt: DateTime.utc(2026),
  sourceVersion: 1,
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);
