import 'dart:async';

import 'package:attendiqo_connect/features/parent/data/parent_projection_repository.dart';
import 'package:attendiqo_connect/features/parent/domain/parent_data.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026));

  test('student mapper accepts only the parent-safe projection schema', () {
    final profile = ParentProjectionMapper.student('student-1', {
      'studentId': 'student-1',
      'instituteId': 'institute-1',
      'fullName': 'Safe Child',
      'studentNumber': 'ST-001',
      'grade': 'Grade 8',
      'active': true,
      'classIds': <String>['class-1'],
      'publicProfileImageUrl': null,
      'updatedAt': timestamp,
      'sourceVersion': 2,
      'qrToken': 'ignored-by-allowlisted-mapper',
    });

    expect(profile.fullName, 'Safe Child');
    expect(profile.classIds, ['class-1']);
  });

  test('malformed link identifier is rejected', () {
    expect(
      () => ParentProjectionMapper.link('forged-id', {
        'parentUid': 'parent-1',
        'studentId': 'student-1',
        'instituteId': 'institute-1',
        'relationship': 'parent',
        'active': true,
        'createdAt': timestamp,
        'updatedAt': timestamp,
        'createdBy': 'admin-1',
        'revokedAt': null,
        'revokedBy': null,
        'sourceVersion': 1,
      }),
      throwsFormatException,
    );
  });

  test('protected linked-student profile index is normalized', () {
    expect(
      ParentProjectionMapper.linkedStudentIds({
        'parentLinkedStudentIds': ['student-b', 'student-a', 'student-a'],
      }),
      ['student-a', 'student-b'],
    );
    expect(
      () => ParentProjectionMapper.linkedStudentIds({
        'parentLinkedStudentIds': ['student-a', 7],
      }),
      throwsFormatException,
    );
  });

  test('raw values cannot be substituted for typed timestamps', () {
    expect(
      () => ParentProjectionMapper.attendance('summary-1', {
        'summaryId': 'summary-1',
        'studentId': 'student-1',
        'instituteId': 'institute-1',
        'classId': 'class-1',
        'attendanceDate': '2026-01-01',
        'status': 'present',
        'entryTime': null,
        'exitTime': null,
        'late': false,
        'currentPresenceState': 'outside',
        'updatedAt': timestamp,
        'sourceVersion': 1,
      }),
      throwsFormatException,
    );
  });

  test(
    'selected membership scope filters cross-institute parent links',
    () async {
      final repository = InstituteScopedParentProjectionRepository(
        instituteId: 'selected',
        delegate: _LinkRepository(),
      );

      await expectLater(repository.watchOwnActiveLinks(), emits(hasLength(1)));
      await expectLater(
        repository.watchChildClasses(LinkedChildRecord(link: _link('other'))),
        emitsError(isA<ParentDataException>()),
      );
    },
  );
}

class _LinkRepository extends UnavailableParentProjectionRepository {
  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() =>
      Stream.value([_link('selected'), _link('other')]);
}

ParentStudentLink _link(String instituteId) => ParentStudentLink(
  parentUid: 'parent',
  studentId: 'student-$instituteId',
  instituteId: instituteId,
  relationship: 'Parent',
  active: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  createdBy: 'trusted',
  sourceVersion: 1,
);
