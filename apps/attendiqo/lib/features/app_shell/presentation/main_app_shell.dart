import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/attendiqo_app_shell.dart';
import '../../academic_management/application/academic_management_controller.dart';
import '../../academic_management/data/firestore_academic_repository.dart';
import '../../academic_management/presentation/academic_management_screens.dart';
import '../../authentication/presentation/authentication_screens.dart';
import '../../password_recovery/data/firebase_managed_password_reset_service.dart';
import '../../super_admin/application/super_admin_controller.dart';
import '../../super_admin/data/firestore_institute_repository.dart';
import '../../super_admin/presentation/super_admin_screens.dart';
import '../../teacher_management/application/teacher_management_controller.dart';
import '../../teacher_management/data/firestore_teacher_repository.dart';
import '../../teacher_management/presentation/teacher_management_screens.dart';

/// One state-preserving, role-aware shell. Primary destinations are embedded
/// body views; create, edit and detail screens remain normal pushed routes.
class MainAppShell extends StatefulWidget {
  const MainAppShell({
    super.key,
    required this.authController,
    this.notificationDestination,
  });
  final AuthenticationController authController;
  final ValueListenable<String?>? notificationDestination;

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  AcademicManagementController? _academic;
  TeacherManagementController? _teacherManagement;
  SuperAdminController? _superAdmin;
  String? _instituteName;
  late final bool _firebaseReady;

  @override
  void initState() {
    super.initState();
    _firebaseReady = Firebase.apps.isNotEmpty;
    if (!_firebaseReady) return;
    final profile = widget.authController.state.profile;
    if (profile == null) return;
    if (profile.role != UserRole.superAdmin) {
      _academic = AcademicManagementController(
        actor: profile,
        repository: FirestoreAcademicRepository(),
      )..load();
    }
    if (profile.role == UserRole.instituteAdmin ||
        profile.role == UserRole.superAdmin) {
      _teacherManagement = TeacherManagementController(
        actor: profile,
        repository: FirestoreTeacherRepository(),
        provisioningService: kDebugMode
            ? MockTeacherProvisioningService()
            : const UnavailableTeacherProvisioningService(),
        passwordResetService: FirebaseManagedPasswordResetService(),
        verifiedSuperAdminClaim: profile.role == UserRole.superAdmin,
      )..load();
    }
    if (profile.role == UserRole.superAdmin) {
      _superAdmin = SuperAdminController(
        repository: FirestoreInstituteRepository(),
        provisioningService: kDebugMode
            ? MockInstituteAdminProvisioningService()
            : const UnavailableInstituteAdminProvisioningService(),
        passwordResetService: FirebaseManagedPasswordResetService(),
        actor: profile,
      )..load();
    }
    _resolveInstituteName(profile);
  }

  Future<void> _resolveInstituteName(UserProfile profile) async {
    if (profile.instituteId == null || profile.role == UserRole.teacher) return;
    try {
      final institute = await FirestoreInstituteRepository().fetchInstituteById(
        profile.instituteId!,
      );
      if (mounted) setState(() => _instituteName = institute?.name);
    } catch (_) {
      // Use the safe non-ID fallback below. Raw Firestore errors never render.
    }
  }

  @override
  void dispose() {
    _academic?.dispose();
    _teacherManagement?.dispose();
    _superAdmin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.authController.state.profile;
    if (profile == null) {
      return AccessBlockedScreen(
        message:
            'Your account profile could not be loaded. Please sign in again.',
        onSignOut: widget.authController.signOut,
      );
    }
    if (!_firebaseReady) {
      return AttendiqoAppShell(
        profile: profile,
        authController: widget.authController,
        destinations: [
          _destination(
            profile.role == UserRole.superAdmin ? 'Overview' : 'Home',
            Icons.home_outlined,
            Icons.home,
            _RuntimeUnavailableHome(profile: profile),
          ),
        ],
        onSignOut: widget.authController.signOut,
        notificationDestination: widget.notificationDestination,
      );
    }
    final instituteName = _instituteName ?? 'Institute information';
    final destinations = switch (profile.role) {
      UserRole.instituteAdmin => _admin(profile, instituteName),
      UserRole.teacher => _teacher(profile, instituteName),
      UserRole.superAdmin => _super(profile),
      _ => const <RoleNavigationDestination>[],
    };
    return AttendiqoAppShell(
      profile: profile,
      authController: widget.authController,
      instituteName: profile.role == UserRole.superAdmin ? null : instituteName,
      destinations: destinations,
      onSignOut: widget.authController.signOut,
      notificationDestination: widget.notificationDestination,
    );
  }

  List<RoleNavigationDestination> _admin(
    UserProfile profile,
    String instituteName,
  ) {
    final academic = _academic!;
    final teachers = _teacherManagement!;
    return [
      _destination(
        'Home',
        Icons.home_outlined,
        Icons.home,
        _AdminHome(
          profile: profile,
          instituteName: instituteName,
          academic: academic,
          teachers: teachers,
        ),
      ),
      _destination(
        'People',
        Icons.people_outline,
        Icons.people,
        _TabbedBody(
          labels: const ['Students', 'Teachers'],
          pages: [
            RefreshIndicator(
              onRefresh: academic.load,
              child: StudentListScreen(controller: academic),
            ),
            _TeacherList(controller: teachers),
          ],
        ),
      ),
      _destination(
        'Classes',
        Icons.class_outlined,
        Icons.class_,
        _ClassesBody(controller: academic),
      ),
      _destination(
        'Attendance',
        Icons.fact_check_outlined,
        Icons.fact_check,
        const _UnavailableTabs(
          labels: ['Live', 'Sessions', 'Corrections'],
          title: 'Attendance backend not deployed',
          message:
              'Scanner, sessions and corrections remain behind the reviewed trusted backend.',
        ),
      ),
      _destination(
        'More',
        Icons.more_horiz,
        Icons.more,
        _MoreBody(
          title: 'Institute settings',
          groups: const {
            'Institute': [
              'Institute profile',
              'Academic year',
              'Rooms and locations',
            ],
            'Management': [
              'Teacher permissions',
              'Student assignments',
              'QR cards',
              'Audit logs',
            ],
            'Reports': [
              'Attendance reports',
              'Student reports',
              'Class reports',
            ],
            'System': ['Account', 'Security', 'Help and support'],
          },
          onSignOut: widget.authController.signOut,
        ),
      ),
    ];
  }

  List<RoleNavigationDestination> _teacher(
    UserProfile profile,
    String instituteName,
  ) {
    final academic = _academic!;
    final permissions = profile.effectiveTeacherPermissions;
    return [
      _destination(
        'Home',
        Icons.home_outlined,
        Icons.home,
        _TeacherHome(
          profile: profile,
          instituteName: instituteName,
          academic: academic,
        ),
      ),
      _destination(
        'My Classes',
        Icons.class_outlined,
        Icons.class_,
        _ClassesBody(controller: academic, teacherView: true),
      ),
      _destination(
        'Attendance',
        Icons.fact_check_outlined,
        Icons.fact_check,
        const _UnavailableTabs(
          labels: ['Live', 'Sessions', 'Corrections'],
          title: 'Attendance backend not deployed',
          message: 'Only the approved trusted backend can persist attendance.',
        ),
      ),
      if (permissions.canAddStudents || permissions.canEditStudents)
        _destination(
          'Students',
          Icons.people_outline,
          Icons.people,
          const _BoundaryPanel(
            title: 'Student records are not configured',
            message:
                'A redacted trusted projection is required before teacher student or parent-contact data can be read safely.',
          ),
        ),
      _destination(
        'Profile',
        Icons.person_outline,
        Icons.person,
        _TeacherProfile(
          profile: profile,
          instituteName: instituteName,
          academic: academic,
          onSignOut: widget.authController.signOut,
        ),
      ),
    ];
  }

  List<RoleNavigationDestination> _super(UserProfile profile) {
    final controller = _superAdmin!;
    return [
      _destination(
        'Overview',
        Icons.dashboard_outlined,
        Icons.dashboard,
        _SuperOverview(profile: profile, controller: controller),
      ),
      _destination(
        'Institutes',
        Icons.apartment_outlined,
        Icons.apartment,
        _InstituteList(controller: controller),
      ),
      _destination(
        'Monitoring',
        Icons.monitor_heart_outlined,
        Icons.monitor_heart,
        const _BoundaryPanel(
          title: 'Operational monitoring',
          message:
              'The trusted backend, notification and SMS services are not deployed. Rules and indexes require human review before deployment.',
        ),
      ),
      _destination(
        'Audit',
        Icons.history_outlined,
        Icons.history,
        _AuditList(controller: controller),
      ),
      _destination(
        'More',
        Icons.more_horiz,
        Icons.more,
        _MoreBody(
          title: 'Platform settings',
          groups: const {
            'System': [
              'Backend status',
              'Rules and index review',
              'Notification configuration',
            ],
            'Support': ['Security review', 'Help and support'],
          },
          onSignOut: widget.authController.signOut,
        ),
      ),
    ];
  }
}

RoleNavigationDestination _destination(
  String label,
  IconData icon,
  IconData selectedIcon,
  Widget page,
) => RoleNavigationDestination(
  label: label,
  icon: icon,
  selectedIcon: selectedIcon,
  page: page,
);

class _RuntimeUnavailableHome extends StatelessWidget {
  const _RuntimeUnavailableHome({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      RoleDashboardHeader(
        profile: profile,
        roleLabel: profile.role.name,
        icon: Icons.shield_outlined,
        subtitle: 'Signed-in foundation mode.',
      ),
      const SizedBox(height: 20),
      const AppStatePanel(
        icon: Icons.cloud_off_outlined,
        title: 'Data services unavailable',
        message:
            'Firebase data services are not available in this runtime. Please try again when the app is configured.',
      ),
    ],
  );
}

class _AdminHome extends StatelessWidget {
  const _AdminHome({
    required this.profile,
    required this.instituteName,
    required this.academic,
    required this.teachers,
  });
  final UserProfile profile;
  final String instituteName;
  final AcademicManagementController academic;
  final TeacherManagementController teachers;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([academic, teachers]),
    builder: (_, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RoleDashboardHeader(
          profile: profile,
          roleLabel: 'Institute Admin',
          instituteName: instituteName,
          icon: Icons.admin_panel_settings_outlined,
          subtitle: 'Full management access inside your institute.',
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Quick actions'),
        const SizedBox(height: 12),
        _Actions(
          actions: [
            _Action(
              'Add Teacher',
              Icons.person_add_alt_1,
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreateTeacherScreen(controller: teachers),
                ),
              ),
            ),
            _Action(
              'Create Class',
              Icons.add_business_outlined,
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreateClassScreen(controller: academic),
                ),
              ),
            ),
            _Action(
              'Add Student',
              Icons.person_add_alt_1_outlined,
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreateStudentScreen(controller: academic),
                ),
              ),
            ),
            _Action(
              'Start Attendance',
              Icons.qr_code_scanner_outlined,
              () => _notConfigured(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Today at a glance'),
        const SizedBox(height: 12),
        OverviewMetricGrid(
          children: [
            StatisticCard(
              label: 'Teachers',
              value: '${teachers.teachers.length}',
              icon: Icons.groups_outlined,
            ),
            StatisticCard(
              label: 'Classes',
              value: '${academic.classes.length}',
              icon: Icons.class_outlined,
            ),
            StatisticCard(
              label: 'Students',
              value: '${academic.students.length}',
              icon: Icons.people_outline,
            ),
            const StatisticCard(
              label: 'Open sessions',
              value: '—',
              icon: Icons.timer_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const ActionRequiredCard(
          title: 'Trusted backend pending',
          message:
              'QR scanning, attendance sessions and corrections remain unavailable until the reviewed backend is deployed.',
        ),
      ],
    ),
  );
}

class _TeacherHome extends StatelessWidget {
  const _TeacherHome({
    required this.profile,
    required this.instituteName,
    required this.academic,
  });
  final UserProfile profile;
  final String instituteName;
  final AcademicManagementController academic;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: academic,
    builder: (_, _) {
      final permissions = profile.effectiveTeacherPermissions;
      final today = academic.classes
          .where(
            (item) =>
                item.active &&
                item.daysOfWeek.contains(
                  ClassWeekday.values[DateTime.now().weekday - 1],
                ),
          )
          .toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RoleDashboardHeader(
            profile: profile,
            roleLabel: 'Teacher',
            instituteName: instituteName,
            icon: Icons.co_present_rounded,
            subtitle: 'Your assigned work and effective schedule.',
          ),
          const SizedBox(height: 24),
          CurrentOrNextClassCard(
            message: today.isEmpty
                ? 'No class is scheduled today.'
                : '${today.first.name} • ${today.first.scheduleLabel}',
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Quick actions'),
          const SizedBox(height: 12),
          _Actions(
            actions: [
              if (permissions.canCreateClasses)
                _Action(
                  'Create Class',
                  Icons.add_business_outlined,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CreateClassScreen(controller: academic),
                    ),
                  ),
                ),
              if (permissions.canAddStudents)
                _Action(
                  'Add Student',
                  Icons.person_add_alt_1_outlined,
                  () => _notConfigured(context),
                ),
              if (permissions.canGenerateQrCodes)
                _Action(
                  'Generate QR',
                  Icons.qr_code_2,
                  () => _notConfigured(context),
                ),
              if (permissions.canTakeAttendance)
                _Action(
                  'Start Attendance',
                  Icons.qr_code_scanner_outlined,
                  () => _notConfigured(context),
                ),
              if (permissions.canCorrectAttendance)
                _Action(
                  'Correct Attendance',
                  Icons.edit_calendar_outlined,
                  () => _notConfigured(context),
                ),
              if (permissions.canExportReports)
                _Action(
                  'Export Report',
                  Icons.ios_share_outlined,
                  () => _notConfigured(context),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Today’s classes'),
          const SizedBox(height: 12),
          if (today.isEmpty)
            const AppStatePanel.empty(
              title: 'No classes today',
              message:
                  'Your running and upcoming assigned classes appear here.',
            )
          else
            ...today.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text('${item.subject} • ${item.scheduleLabel}'),
                  trailing: AppStatusChip(label: item.status.name),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const AppStatePanel.empty(
            title: 'No notices',
            message: 'Approved schedule changes will appear here.',
          ),
        ],
      );
    },
  );
}

class _TabbedBody extends StatelessWidget {
  const _TabbedBody({required this.labels, required this.pages});
  final List<String> labels;
  final List<Widget> pages;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: labels.length,
    child: Column(
      children: [
        TabBar(tabs: labels.map((label) => Tab(text: label)).toList()),
        Expanded(child: TabBarView(children: pages)),
      ],
    ),
  );
}

class _ClassesBody extends StatelessWidget {
  const _ClassesBody({required this.controller, this.teacherView = false});
  final AcademicManagementController controller;
  final bool teacherView;
  @override
  Widget build(BuildContext context) => _TabbedBody(
    labels: const ['Today', 'All classes', 'Schedule'],
    pages: [
      _TodayClasses(controller: controller),
      RefreshIndicator(
        onRefresh: controller.refreshClasses,
        child: ClassListScreen(controller: controller),
      ),
      _ScheduleChanges(controller: controller),
    ],
  );
}

/*
class _TodayClasses extends StatelessWidget {
  const _TodayClasses({required this.controller});
  final AcademicManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (_, _) {
    final day = ClassWeekday.values[DateTime.now().weekday - 1];
    final classes = controller.classes.where((item) => item.active && item.daysOfWeek.contains(day)).toList();
    return RefreshIndicator(onRefresh: controller.refreshClasses, child: ListView(padding: const EdgeInsets.all(16), children: [
      const SectionHeader(title: 'Today’s classes'),
      const SizedBox(height: 12),
      if (controller.loading) const LoadingStatePanel() else if (controller.error != null) AppStatePanel.error(title: 'Unable to load classes', message: controller.error!) else if (classes.isEmpty) const AppStatePanel.empty(title: 'No classes today', message: 'Running and upcoming classes will appear here.') else ...classes.map((item) => Card(child: ListTile(leading: const Icon(Icons.schedule_outlined), title: Text(item.name), subtitle: Text(item.scheduleLabel), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ClassDetailsScreen(controller: controller, academicClass: item))))),
    ]));
  });
}

*/
class _TodayClasses extends StatelessWidget {
  const _TodayClasses({required this.controller});
  final AcademicManagementController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final day = ClassWeekday.values[DateTime.now().weekday - 1];
      final classes = controller.classes
          .where((item) => item.active && item.daysOfWeek.contains(day))
          .toList();
      return RefreshIndicator(
        onRefresh: controller.refreshClasses,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(title: 'Today classes'),
            const SizedBox(height: 12),
            if (controller.loading)
              const LoadingStatePanel()
            else if (controller.error != null)
              AppStatePanel.error(
                title: 'Unable to load classes',
                message: controller.error!,
              )
            else if (classes.isEmpty)
              const AppStatePanel.empty(
                title: 'No classes today',
                message: 'Running and upcoming classes will appear here.',
              )
            else
              for (final item in classes)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(item.name),
                    subtitle: Text(item.scheduleLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ClassDetailsScreen(
                          controller: controller,
                          academicClass: item,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _ScheduleChanges extends StatelessWidget {
  const _ScheduleChanges({required this.controller});
  final AcademicManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(title: 'Weekly schedule'),
        const SizedBox(height: 12),
        if (controller.scheduleChanges.isEmpty)
          const AppStatePanel.empty(
            title: 'No schedule changes',
            message:
                'Effective temporary changes and conflicts will appear here.',
          )
        else
          ...controller.scheduleChanges.map(
            (item) => Card(
              child: ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: Text(item.reason),
                trailing: AppStatusChip(label: item.status.name),
              ),
            ),
          ),
      ],
    ),
  );
}

class _TeacherList extends StatelessWidget {
  const _TeacherList({required this.controller});
  final TeacherManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search teachers',
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TeacherFilter.values
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter.name),
                        selected: controller.filter == filter,
                        onSelected: (_) => controller.setFilter(filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: controller.saving
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CreateTeacherScreen(controller: controller),
                      ),
                    ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Teacher'),
            ),
          ),
          if (controller.loading)
            const LoadingStatePanel()
          else if (controller.error != null)
            AppStatePanel.error(
              title: 'Unable to load teachers',
              message: controller.error!,
            )
          else if (controller.visibleTeachers.isEmpty)
            const AppStatePanel.empty(
              title: 'No teachers found',
              message: 'Create a teacher or adjust filters.',
            )
          else
            ...controller.visibleTeachers.map(
              (teacher) => TeacherListCard(
                teacher: teacher,
                canEdit: controller.canEditTeacher(teacher),
                updateInProgress: controller.saving,
                onEdit: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EditTeacherScreen(
                      controller: controller,
                      teacher: teacher,
                    ),
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => TeacherDetailsScreen(
                      controller: controller,
                      initialTeacher: teacher,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _UnavailableTabs extends StatelessWidget {
  const _UnavailableTabs({
    required this.labels,
    required this.title,
    required this.message,
  });
  final List<String> labels;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => _TabbedBody(
    labels: labels,
    pages: List.generate(
      labels.length,
      (_) => _BoundaryPanel(title: title, message: message),
    ),
  );
}

class _BoundaryPanel extends StatelessWidget {
  const _BoundaryPanel({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AppStatePanel(
        icon: Icons.cloud_off_outlined,
        title: title,
        message: message,
      ),
    ),
  );
}

class _TeacherProfile extends StatelessWidget {
  const _TeacherProfile({
    required this.profile,
    required this.instituteName,
    required this.academic,
    required this.onSignOut,
  });
  final UserProfile profile;
  final String instituteName;
  final AcademicManagementController academic;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      RoleDashboardHeader(
        profile: profile,
        roleLabel: 'Teacher',
        instituteName: instituteName,
        icon: Icons.badge_outlined,
        subtitle: 'Account and assigned work.',
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DetailInformationRow(
                label: 'Employee number',
                value: profile.employeeNumber ?? 'Not provided',
              ),
              DetailInformationRow(label: 'Institute', value: instituteName),
              DetailInformationRow(
                label: 'Assigned classes',
                value: '${academic.classes.length}',
              ),
              DetailInformationRow(
                label: 'Account status',
                value: profile.active ? 'Active' : 'Inactive',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );
}

class _SuperOverview extends StatelessWidget {
  const _SuperOverview({required this.profile, required this.controller});
  final UserProfile profile;
  final SuperAdminController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final stats = controller.statistics;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RoleDashboardHeader(
            profile: profile,
            roleLabel: 'Verified Super Admin',
            icon: Icons.admin_panel_settings_outlined,
            subtitle: 'Attendiqo Control Centre',
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Platform status'),
          const SizedBox(height: 12),
          OverviewMetricGrid(
            children: [
              StatisticCard(
                label: 'Institutes',
                value: '${stats.totalInstitutes}',
                icon: Icons.apartment_outlined,
              ),
              StatisticCard(
                label: 'Active institutes',
                value: '${stats.activeInstitutes}',
                icon: Icons.verified_outlined,
              ),
              StatisticCard(
                label: 'Suspended',
                value: '${stats.suspendedInstitutes}',
                icon: Icons.pause_circle_outline,
              ),
              StatisticCard(
                label: 'SMS enabled',
                value: '${stats.smsEnabledInstitutes}',
                icon: Icons.sms_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const ActionRequiredCard(
            title: 'Platform attention',
            message:
                'Production QR/attendance, notifications and SMS remain intentionally unconfigured.',
          ),
        ],
      );
    },
  );
}

/*
class _InstituteList extends StatelessWidget {
  const _InstituteList({required this.controller});
  final SuperAdminController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (_, _) => RefreshIndicator(onRefresh: controller.load, child: ListView(padding: const EdgeInsets.all(16), children: [TextField(onChanged: controller.setSearch, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search institutes')), const SizedBox(height: 8), SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: InstituteFilter.values.map((filter) => Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(filter.name), selected: controller.filter == filter, onSelected: (_) => controller.setFilter(filter)))).toList())), const SizedBox(height: 12), if (controller.loading) const LoadingStatePanel() else if (controller.error != null) AppStatePanel.error(title: 'Unable to load institutes', message: controller.error!) else if (controller.visibleInstitutes.isEmpty) const AppStatePanel.empty(title: 'No institutes found', message: 'Adjust the current search or filter.') else ...controller.visibleInstitutes.map((institute) => Card(child: ListTile(leading: CircleAvatar(child: Text(institute.instituteCode.substring(0, 1))), title: Text(institute.name), subtitle: Text(institute.instituteCode), trailing: AppStatusChip(label: institute.status.name), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => InstituteDetailsScreen(controller: controller, institute: institute)))))])));
}

*/
class _InstituteList extends StatelessWidget {
  const _InstituteList({required this.controller});
  final SuperAdminController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search institutes',
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: InstituteFilter.values
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter.name),
                        selected: controller.filter == filter,
                        onSelected: (_) => controller.setFilter(filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (controller.loading)
            const LoadingStatePanel()
          else if (controller.error != null)
            AppStatePanel.error(
              title: 'Unable to load institutes',
              message: controller.error!,
            )
          else if (controller.visibleInstitutes.isEmpty)
            const AppStatePanel.empty(
              title: 'No institutes found',
              message: 'Adjust the current search or filter.',
            )
          else
            for (final institute in controller.visibleInstitutes)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(institute.instituteCode.substring(0, 1)),
                  ),
                  title: Text(institute.name),
                  subtitle: Text(institute.instituteCode),
                  trailing: AppStatusChip(label: institute.status.name),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InstituteDetailsScreen(
                        controller: controller,
                        institute: institute,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.controller});
  final SuperAdminController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(title: 'Platform audit'),
        const SizedBox(height: 12),
        if (controller.loading)
          const LoadingStatePanel()
        else if (controller.error != null)
          AppStatePanel.error(
            title: 'Unable to load audit history',
            message: controller.error!,
          )
        else if (controller.auditLogs.isEmpty)
          const AppStatePanel.empty(
            title: 'No audit entries',
            message: 'Append-only platform activity will appear here.',
          )
        else
          ...controller.auditLogs
              .take(100)
              .map(
                (entry) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: Text(entry.action.name),
                    subtitle: Text(entry.summary),
                    trailing: const Icon(Icons.lock_outline, size: 18),
                  ),
                ),
              ),
      ],
    ),
  );
}

class _MoreBody extends StatelessWidget {
  const _MoreBody({
    required this.title,
    required this.groups,
    required this.onSignOut,
  });
  final String title;
  final Map<String, List<String>> groups;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      ...groups.entries.expand(
        (entry) => [
          SectionHeader(title: entry.key),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: entry.value
                  .map(
                    (label) => ListTile(
                      title: Text(label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _notConfigured(context),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
      OutlinedButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );
}

class _Action {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/*
class _Actions extends StatelessWidget {
  const _Actions({required this.actions});
  final List<_Action> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, constraints) => GridView.count(crossAxisCount: constraints.maxWidth >= 620 ? 4 : 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.3, children: actions.map((action) => Card(child: InkWell(borderRadius: BorderRadius.circular(16), onTap: action.onTap, child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(action.icon), const SizedBox(height: 8), Text(action.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)])))).toList()));
}

*/
class _Actions extends StatelessWidget {
  const _Actions({required this.actions});
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => GridView.count(
      crossAxisCount: constraints.maxWidth >= 620 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        for (final action in actions)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: action.onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon),
                    const SizedBox(height: 8),
                    Text(
                      action.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

void _notConfigured(
  BuildContext context,
) => ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text(
      'This action needs the reviewed trusted backend and is not configured yet.',
    ),
  ),
);
