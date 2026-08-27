import 'dart:async';

import 'package:attendiqo_connect/app/connect_app.dart';
import 'package:attendiqo_connect/features/parent/data/parent_projection_repository.dart';
import 'package:attendiqo_connect/features/parent/domain/parent_data.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('projection-backed phone UI shows safe data without raw IDs', (
    tester,
  ) async {
    final auth = _AuthRepository();
    await tester.pumpWidget(
      AttendiqoConnectApp(
        authenticationRepository: auth,
        parentProjectionRepository: _ProjectionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Safe Child'), findsWidgets);
    expect(find.text('Safe Institute'), findsWidgets);
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('student-internal-1'), findsNothing);
    expect(find.text('institute-internal-1'), findsNothing);

    await tester.tap(find.text('Notices').last);
    await tester.pumpAndSettle();
    expect(find.text('School holiday'), findsOneWidget);
    expect(find.text('notice-internal-1'), findsNothing);

    await tester.tap(find.text('Attendance').last);
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Edit attendance'), findsNothing);

    await auth.dispose();
  });

  testWidgets('tablet uses NavigationRail and keeps visited tab state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _AuthRepository();
    await tester.pumpWidget(
      AttendiqoConnectApp(
        authenticationRepository: auth,
        parentProjectionRepository: _ProjectionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Children').last);
    await tester.pumpAndSettle();
    expect(find.text('Assigned classes'), findsOneWidget);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Quick actions'), findsOneWidget);

    await auth.dispose();
  });

  testWidgets('narrow phone and large text render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = _AuthRepository();
    await tester.pumpWidget(
      AttendiqoConnectApp(
        authenticationRepository: auth,
        parentProjectionRepository: _ProjectionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);

    await auth.dispose();
  });
}

class _AuthRepository
    implements AuthenticationRepository, ActiveMembershipRepository {
  final _changes = StreamController<AuthenticatedUser?>.broadcast();

  @override
  Stream<AuthenticatedUser?> authStateChanges() async* {
    yield const AuthenticatedUser(uid: 'parent-1', email: 'parent@example.com');
    yield* _changes.stream;
  }

  @override
  Future<UserProfile?> loadProfile(String uid) async => UserProfile(
    uid: uid,
    email: 'parent@example.com',
    displayName: 'Test Parent',
    role: UserRole.parent,
    instituteId: null,
    active: true,
    mustChangePassword: false,
    createdAt: DateTime.utc(2026),
    createdBy: 'trusted-system',
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<List<InstituteMembership>> loadOwnMemberships(
    String authenticatedUid,
  ) async => [
    InstituteMembership(
      uid: authenticatedUid,
      instituteId: 'institute-internal-1',
      role: UserRole.parent,
      status: InstituteMembershipStatus.active,
      requestedAt: DateTime.utc(2026),
    ),
  ];

  @override
  Future<void> markLastLogin(String uid) async {}
  @override
  Future<void> clearMustChangePassword(String uid) async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async => AuthenticatedUser(uid: 'parent-1', email: email);
  @override
  Future<void> signOut() async => _changes.add(null);
  @override
  Future<void> updatePassword(String newPassword) async {}
  Future<void> dispose() => _changes.close();
}

class _ProjectionRepository implements ParentProjectionRepository {
  final ParentStudentLink link = ParentStudentLink(
    parentUid: 'parent-1',
    studentId: 'student-internal-1',
    instituteId: 'institute-internal-1',
    relationship: 'Parent',
    active: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    createdBy: 'trusted-admin',
    sourceVersion: 1,
  );

  late final ParentStudentProfile student = ParentStudentProfile(
    studentId: link.studentId,
    instituteId: link.instituteId,
    fullName: 'Safe Child',
    studentNumber: 'ST-001',
    grade: 'Grade 8',
    active: true,
    classIds: const ['class-internal-1'],
    updatedAt: DateTime.utc(2026),
    sourceVersion: 1,
  );

  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() => Stream.value([link]);

  @override
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  ) => Stream.value([LinkedChildRecord(link: link, profile: student)]);

  @override
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) => Stream.value(studentId == link.studentId ? student : null);

  @override
  Stream<List<ProjectedClassRecord>> watchChildClasses(
    LinkedChildRecord child,
  ) => Stream.value([
    ProjectedClassRecord(
      classId: 'class-internal-1',
      profile: ParentClassProfile(
        classId: 'class-internal-1',
        instituteId: link.instituteId,
        className: 'Mathematics',
        subject: 'Maths',
        grade: 'Grade 8',
        room: 'Room 4',
        normalSchedule: const {'startTime': '09:00', 'endTime': '10:00'},
        active: true,
        updatedAt: DateTime.utc(2026),
        sourceVersion: 1,
      ),
    ),
  ]);

  @override
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  ) {
    final now = DateTime.now();
    return Stream.value([
      ParentAttendanceSummary(
        summaryId: 'safe-summary',
        studentId: link.studentId,
        instituteId: link.instituteId,
        classId: 'class-internal-1',
        attendanceDate: DateTime(now.year, now.month, now.day),
        status: 'present',
        late: false,
        currentPresenceState: 'inside',
        entryTime: DateTime(now.year, now.month, now.day, 9),
        updatedAt: now,
        sourceVersion: 1,
      ),
    ]);
  }

  @override
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child) =>
      Stream.value([
        ParentNotice(
          noticeId: 'notice-internal-1',
          instituteId: link.instituteId,
          title: 'School holiday',
          message: 'The institute will be closed tomorrow.',
          publishedAt: DateTime.now(),
          priority: ParentNoticePriority.normal,
          active: true,
          targetType: ParentNoticeTargetType.instituteParents,
          updatedAt: DateTime.now(),
          sourceVersion: 1,
        ),
      ]);

  @override
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  ) => Stream.value(
    InstitutePublicProfile(
      instituteId: instituteId,
      displayName: 'Safe Institute',
      status: 'active',
      publicEmail: 'contact@example.com',
      updatedAt: DateTime.utc(2026),
      sourceVersion: 1,
    ),
  );
}
