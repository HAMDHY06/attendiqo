import 'dart:async';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/parent_data.dart';

abstract interface class ParentProjectionRepository {
  Stream<List<ParentStudentLink>> watchOwnActiveLinks();
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  );
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  );
  Stream<List<ProjectedClassRecord>> watchChildClasses(LinkedChildRecord child);
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  );
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child);
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  );
}

/// Session-only scope wrapper. It prevents a selected membership in one
/// institute from being used to render or request another institute's parent
/// projection data, even when the account has multiple approved memberships.
class InstituteScopedParentProjectionRepository
    implements ParentProjectionRepository {
  const InstituteScopedParentProjectionRepository({
    required this.delegate,
    required this.instituteId,
  });

  final ParentProjectionRepository delegate;
  final String instituteId;

  Stream<T> _denied<T>() => Stream<T>.error(
    const ParentDataException(
      ParentDataFailureKind.permissionDenied,
      'This information is not available for the selected institute.',
    ),
  );

  bool _inScope(ParentStudentLink link) =>
      link.active && link.instituteId == instituteId;

  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() => delegate
      .watchOwnActiveLinks()
      .map((links) => links.where(_inScope).toList(growable: false));

  @override
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  ) => delegate.watchLinkedChildren(
    links.where(_inScope).toList(growable: false),
  );

  @override
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) {
    final links = activeLinks.where(_inScope).toList(growable: false);
    if (!links.any((link) => link.studentId == studentId)) return _denied();
    return delegate.watchChildProfile(studentId, links);
  }

  @override
  Stream<List<ProjectedClassRecord>> watchChildClasses(
    LinkedChildRecord child,
  ) => child.link.instituteId == instituteId && child.link.active
      ? delegate.watchChildClasses(child)
      : _denied();

  @override
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  ) => child.link.instituteId == instituteId && child.link.active
      ? delegate.watchChildAttendance(child, filters)
      : _denied();

  @override
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child) =>
      child.link.instituteId == instituteId && child.link.active
      ? delegate.watchApplicableNotices(child)
      : _denied();

  @override
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  ) {
    if (instituteId != this.instituteId || !activeLinks.any(_inScope)) {
      return _denied();
    }
    return delegate.watchLinkedInstituteProfile(
      instituteId,
      activeLinks.where(_inScope).toList(growable: false),
    );
  }
}

class UnavailableParentProjectionRepository
    implements ParentProjectionRepository {
  const UnavailableParentProjectionRepository();

  Stream<T> _unavailable<T>() => Stream<T>.error(
    const ParentDataException(
      ParentDataFailureKind.unavailable,
      'Parent information is not available because the trusted service is not configured yet.',
    ),
  );

  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() => _unavailable();
  @override
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  ) => _unavailable();
  @override
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) => _unavailable();
  @override
  Stream<List<ProjectedClassRecord>> watchChildClasses(
    LinkedChildRecord child,
  ) => _unavailable();
  @override
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  ) => _unavailable();
  @override
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child) =>
      _unavailable();
  @override
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  ) => _unavailable();
}

class FirestoreParentProjectionRepository
    implements ParentProjectionRepository {
  FirestoreParentProjectionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const maxChildren = 20;
  static const maxClasses = 30;
  static const maxAttendanceRecords = 100;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const ParentDataException(
        ParentDataFailureKind.unauthenticated,
        'Your session has expired. Please sign in again.',
      );
    }
    return uid;
  }

  @override
  Stream<List<ParentStudentLink>> watchOwnActiveLinks() {
    final uid = _uid();
    late StreamController<List<ParentStudentLink>> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    profileSubscription;
    StreamSubscription<List<ParentStudentLink>>? linksSubscription;
    var scopeGeneration = 0;
    controller = StreamController<List<ParentStudentLink>>(
      onListen: () {
        profileSubscription = _firestore
            .collection(FirestoreCollections.users)
            .doc(uid)
            .snapshots()
            .listen(
              (profile) async {
                final generation = ++scopeGeneration;
                await linksSubscription?.cancel();
                linksSubscription = null;
                if (generation != scopeGeneration) return;
                try {
                  if (!profile.exists) {
                    throw const ParentDataException(
                      ParentDataFailureKind.unavailable,
                      'Your parent profile is not available.',
                    );
                  }
                  final studentIds = ParentProjectionMapper.linkedStudentIds(
                    profile.data()!,
                  );
                  if (studentIds.isEmpty) {
                    controller.add(const []);
                    return;
                  }
                  if (studentIds.length > maxChildren) {
                    throw const ParentDataException(
                      ParentDataFailureKind.unavailable,
                      'Too many linked records were returned. Contact your institute.',
                    );
                  }
                  linksSubscription =
                      _combineDocuments<ParentStudentLink>(
                            studentIds.map(
                              (studentId) => _firestore
                                  .collection(
                                    FirestoreCollections.parentStudentLinks,
                                  )
                                  .doc('${uid}_$studentId')
                                  .snapshots()
                                  .map((document) {
                                    if (!document.exists) {
                                      throw const ParentDataException(
                                        ParentDataFailureKind.unavailable,
                                        'Linked-child information is temporarily unavailable.',
                                      );
                                    }
                                    final link = ParentProjectionMapper.link(
                                      document.id,
                                      document.data()!,
                                    );
                                    if (link.parentUid != uid || !link.active) {
                                      throw const ParentDataException(
                                        ParentDataFailureKind.unlinked,
                                        'A child link is no longer active.',
                                      );
                                    }
                                    return link;
                                  }),
                            ),
                          )
                          .map((links) {
                            final ordered = <ParentStudentLink>[...links]
                              ..sort(
                                (left, right) =>
                                    left.createdAt.compareTo(right.createdAt),
                              );
                            return List<ParentStudentLink>.unmodifiable(
                              ordered,
                            );
                          })
                          .listen(
                            controller.add,
                            onError: (Object error, StackTrace stack) {
                              controller.addError(_safe(error), stack);
                            },
                          );
                } catch (error, stack) {
                  controller.addError(_safe(error), stack);
                }
              },
              onError: (Object error, StackTrace stack) {
                controller.addError(_safe(error), stack);
              },
            );
      },
      onCancel: () async {
        scopeGeneration++;
        await linksSubscription?.cancel();
        await profileSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<LinkedChildRecord>> watchLinkedChildren(
    List<ParentStudentLink> links,
  ) {
    if (links.isEmpty) return Stream.value(const []);
    if (links.length > maxChildren) {
      return Stream.error(
        const ParentDataException(
          ParentDataFailureKind.unavailable,
          'Too many linked records were returned. Contact your institute.',
        ),
      );
    }
    return _combineDocuments<LinkedChildRecord>(
      links.map(
        (link) => _firestore
            .collection(FirestoreCollections.parentStudentProfiles)
            .doc(link.studentId)
            .snapshots()
            .map((snapshot) {
              if (!snapshot.exists) return LinkedChildRecord(link: link);
              final profile = ParentProjectionMapper.student(
                snapshot.id,
                snapshot.data()!,
              );
              if (profile.instituteId != link.instituteId) {
                throw const ParentDataException(
                  ParentDataFailureKind.unavailable,
                  'Child information is temporarily unavailable.',
                );
              }
              return LinkedChildRecord(link: link, profile: profile);
            }),
      ),
    );
  }

  @override
  Stream<ParentStudentProfile?> watchChildProfile(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) {
    final link = _activeLinkForStudent(studentId, activeLinks);
    return _guard(
      _firestore
          .collection(FirestoreCollections.parentStudentProfiles)
          .doc(studentId)
          .snapshots()
          .map((snapshot) {
            if (!snapshot.exists) return null;
            final profile = ParentProjectionMapper.student(
              snapshot.id,
              snapshot.data()!,
            );
            if (profile.instituteId != link.instituteId) {
              throw const ParentDataException(
                ParentDataFailureKind.unavailable,
                'Child information is temporarily unavailable.',
              );
            }
            return profile;
          }),
    );
  }

  @override
  Stream<List<ProjectedClassRecord>> watchChildClasses(
    LinkedChildRecord child,
  ) {
    _requireSelectable(child);
    final classIds = child.profile!.classIds.take(maxClasses).toList();
    if (classIds.isEmpty) return Stream.value(const []);
    return _combineDocuments<ProjectedClassRecord>(
      classIds.map(
        (classId) => _firestore
            .collection(FirestoreCollections.parentClassProfiles)
            .doc(classId)
            .snapshots()
            .map((snapshot) {
              if (!snapshot.exists) {
                return ProjectedClassRecord(classId: classId);
              }
              final profile = ParentProjectionMapper.academicClass(
                snapshot.id,
                snapshot.data()!,
              );
              if (profile.instituteId != child.link.instituteId ||
                  profile.classId != classId) {
                throw const ParentDataException(
                  ParentDataFailureKind.unavailable,
                  'Class information is temporarily unavailable.',
                );
              }
              return ProjectedClassRecord(classId: classId, profile: profile);
            }),
      ),
    ).map((records) {
      final byId = {for (final record in records) record.classId: record};
      return List.unmodifiable(classIds.map((id) => byId[id]!));
    });
  }

  @override
  Stream<List<ParentAttendanceSummary>> watchChildAttendance(
    LinkedChildRecord child,
    AttendanceFilters filters,
  ) {
    _requireSelectable(child);
    final safeLimit = filters.limit.clamp(1, maxAttendanceRecords);
    final allowedClasses = child.profile!.classIds.toSet();
    if (filters.classId != null && !allowedClasses.contains(filters.classId)) {
      return Stream.error(
        const ParentDataException(
          ParentDataFailureKind.unlinked,
          'The requested class is not available for this child.',
        ),
      );
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestoreCollections.parentAttendanceSummaries)
        .where('studentId', isEqualTo: child.link.studentId)
        .where('instituteId', isEqualTo: child.link.instituteId)
        .orderBy('attendanceDate', descending: true);
    if (filters.from != null) {
      query = query.where(
        'attendanceDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(filters.from!),
      );
    }
    if (filters.to != null) {
      query = query.where(
        'attendanceDate',
        isLessThanOrEqualTo: Timestamp.fromDate(filters.to!),
      );
    }
    query = query.limit(safeLimit);
    return _guard(
      query.snapshots().map((snapshot) {
        final records = snapshot.docs
            .map(
              (document) => ParentProjectionMapper.attendance(
                document.id,
                document.data(),
              ),
            )
            .where(
              (record) =>
                  record.instituteId == child.link.instituteId &&
                  allowedClasses.contains(record.classId) &&
                  (filters.from == null ||
                      !record.attendanceDate.isBefore(filters.from!)) &&
                  (filters.to == null ||
                      !record.attendanceDate.isAfter(filters.to!)) &&
                  (filters.status == null || record.status == filters.status) &&
                  (filters.classId == null ||
                      record.classId == filters.classId),
            )
            .toList();
        return List.unmodifiable(records);
      }),
    );
  }

  @override
  Stream<List<ParentNotice>> watchApplicableNotices(LinkedChildRecord child) {
    _requireSelectable(child);
    return Stream.error(
      const ParentDataException(
        ParentDataFailureKind.unavailable,
        'Notices are not available until the trusted parent notice feed is configured.',
      ),
    );
  }

  @override
  Stream<InstitutePublicProfile?> watchLinkedInstituteProfile(
    String instituteId,
    List<ParentStudentLink> activeLinks,
  ) {
    if (!activeLinks.any(
      (link) => link.active && link.instituteId == instituteId,
    )) {
      return Stream.error(
        const ParentDataException(
          ParentDataFailureKind.unlinked,
          'Institute information is not available for this account.',
        ),
      );
    }
    return _guard(
      _firestore
          .collection(FirestoreCollections.institutePublicProfiles)
          .doc(instituteId)
          .snapshots()
          .map(
            (snapshot) => snapshot.exists
                ? ParentProjectionMapper.institute(
                    snapshot.id,
                    snapshot.data()!,
                  )
                : null,
          ),
    );
  }

  ParentStudentLink _activeLinkForStudent(
    String studentId,
    List<ParentStudentLink> activeLinks,
  ) {
    for (final link in activeLinks) {
      if (link.active && link.studentId == studentId) return link;
    }
    throw const ParentDataException(
      ParentDataFailureKind.unlinked,
      'This child is not linked to your account.',
    );
  }

  void _requireSelectable(LinkedChildRecord child) {
    if (!child.isSelectable) {
      throw const ParentDataException(
        ParentDataFailureKind.unlinked,
        'This child is no longer available for your account.',
      );
    }
  }

  Stream<List<T>> _combineDocuments<T>(Iterable<Stream<T>> sources) {
    final streams = sources.toList();
    late StreamController<List<T>> controller;
    final subscriptions = <StreamSubscription<T>>[];
    final values = List<T?>.filled(streams.length, null);
    final loaded = List<bool>.filled(streams.length, false);
    controller = StreamController<List<T>>(
      onListen: () {
        for (var index = 0; index < streams.length; index++) {
          subscriptions.add(
            streams[index].listen(
              (value) {
                values[index] = value;
                loaded[index] = true;
                if (loaded.every((value) => value)) {
                  controller.add(List.unmodifiable(values.cast<T>()));
                }
              },
              onError: (Object error, StackTrace stack) {
                controller.addError(_safe(error), stack);
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Stream<T> _guard<T>(Stream<T> source) async* {
    try {
      yield* source;
    } catch (error) {
      throw _safe(error);
    }
  }

  ParentDataException _safe(Object error) {
    if (error is ParentDataException) return error;
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => const ParentDataException(
          ParentDataFailureKind.permissionDenied,
          'Parent information could not be accessed securely.',
        ),
        'unavailable' ||
        'network-request-failed' ||
        'deadline-exceeded' => const ParentDataException(
          ParentDataFailureKind.network,
          'Parent information is unavailable. Check your connection and retry.',
        ),
        _ => const ParentDataException(
          ParentDataFailureKind.unavailable,
          'Parent information is temporarily unavailable.',
        ),
      };
    }
    return const ParentDataException(
      ParentDataFailureKind.malformed,
      'Parent information is invalid or unavailable.',
    );
  }
}

abstract final class ParentProjectionMapper {
  static List<String> linkedStudentIds(Map<String, dynamic> data) {
    final value = data['parentLinkedStudentIds'];
    if (value == null) return const [];
    final ids = _strings(value).toSet().toList()..sort();
    return List.unmodifiable(ids);
  }

  static ParentStudentLink link(String documentId, Map<String, dynamic> data) {
    final parentUid = _text(data['parentUid']);
    final studentId = _text(data['studentId']);
    if (documentId != '${parentUid}_$studentId') throw const FormatException();
    return ParentStudentLink(
      parentUid: parentUid,
      studentId: studentId,
      instituteId: _text(data['instituteId']),
      relationship: _text(data['relationship']),
      active: _boolean(data['active']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      createdBy: _text(data['createdBy']),
      revokedAt: _optionalDate(data['revokedAt']),
      revokedBy: _optionalText(data['revokedBy']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static ParentStudentProfile student(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final studentId = _text(data['studentId']);
    if (studentId != documentId) throw const FormatException();
    return ParentStudentProfile(
      studentId: studentId,
      instituteId: _text(data['instituteId']),
      fullName: _text(data['fullName']),
      studentNumber: _text(data['studentNumber']),
      grade: _optionalText(data['grade']),
      active: _boolean(data['active']),
      classIds: _strings(data['classIds']),
      publicProfileImageUrl: _optionalText(data['publicProfileImageUrl']),
      updatedAt: _date(data['updatedAt']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static ParentClassProfile academicClass(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final classId = _text(data['classId']);
    if (classId != documentId) throw const FormatException();
    return ParentClassProfile(
      classId: classId,
      instituteId: _text(data['instituteId']),
      className: _text(data['className']),
      subject: _text(data['subject']),
      grade: _optionalText(data['grade']),
      teacherDisplayName: _optionalText(data['teacherDisplayName']),
      room: _optionalText(data['room']),
      normalSchedule: _map(data['normalSchedule']),
      effectiveSchedule: data['effectiveSchedule'] == null
          ? null
          : _map(data['effectiveSchedule']),
      active: _boolean(data['active']),
      updatedAt: _date(data['updatedAt']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static ParentAttendanceSummary attendance(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final summaryId = _text(data['summaryId']);
    if (summaryId != documentId) throw const FormatException();
    return ParentAttendanceSummary(
      summaryId: summaryId,
      studentId: _text(data['studentId']),
      instituteId: _text(data['instituteId']),
      classId: _text(data['classId']),
      attendanceDate: _date(data['attendanceDate']),
      status: _text(data['status']),
      entryTime: _optionalDate(data['entryTime']),
      exitTime: _optionalDate(data['exitTime']),
      late: _boolean(data['late']),
      currentPresenceState: _text(data['currentPresenceState']),
      updatedAt: _date(data['updatedAt']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static ParentNotice notice(String documentId, Map<String, dynamic> data) {
    final noticeId = _text(data['noticeId']);
    if (noticeId != documentId) throw const FormatException();
    final target = switch (_text(data['targetType'])) {
      'instituteParents' => ParentNoticeTargetType.instituteParents,
      'student' => ParentNoticeTargetType.student,
      'class' => ParentNoticeTargetType.classTarget,
      _ => throw const FormatException(),
    };
    return ParentNotice(
      noticeId: noticeId,
      instituteId: _text(data['instituteId']),
      title: _text(data['title']),
      message: _text(data['message']),
      publishedAt: _date(data['publishedAt']),
      expiresAt: _optionalDate(data['expiresAt']),
      priority: _text(data['priority']) == 'important'
          ? ParentNoticePriority.important
          : ParentNoticePriority.normal,
      active: _boolean(data['active']),
      targetType: target,
      targetStudentIds: _strings(data['targetStudentIds']),
      targetClassIds: _strings(data['targetClassIds']),
      updatedAt: _date(data['updatedAt']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static InstitutePublicProfile institute(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final instituteId = _text(data['instituteId']);
    if (instituteId != documentId) throw const FormatException();
    return InstitutePublicProfile(
      instituteId: instituteId,
      displayName: _text(data['displayName']),
      logoUrl: _optionalText(data['logoUrl']),
      publicPhone: _optionalText(data['publicPhone']),
      publicEmail: _optionalText(data['publicEmail']),
      publicAddress: _optionalText(data['publicAddress']),
      status: _text(data['status']),
      updatedAt: _date(data['updatedAt']),
      sourceVersion: _integer(data['sourceVersion']),
    );
  }

  static String _text(Object? value) =>
      value is String && value.trim().isNotEmpty
      ? value.trim()
      : throw const FormatException();
  static String? _optionalText(Object? value) => value == null
      ? null
      : value is String
      ? (value.trim().isEmpty ? null : value.trim())
      : throw const FormatException();
  static bool _boolean(Object? value) =>
      value is bool ? value : throw const FormatException();
  static int _integer(Object? value) =>
      value is int && value >= 0 ? value : throw const FormatException();
  static DateTime _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date,
    _ => throw const FormatException(),
  };
  static DateTime? _optionalDate(Object? value) =>
      value == null ? null : _date(value);
  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.map(_text))
      : throw const FormatException();
  static Map<String, Object?> _map(Object? value) => value is Map
      ? Map.unmodifiable(
          value.map((key, item) => MapEntry(key.toString(), item)),
        )
      : throw const FormatException();
}
