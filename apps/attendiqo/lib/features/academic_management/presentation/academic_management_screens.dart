import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../application/academic_management_controller.dart';
import '../data/firestore_academic_repository.dart';
import '../../attendance/presentation/attendance_screens.dart';

class AcademicManagementArea extends StatefulWidget {
  const AcademicManagementArea({
    super.key,
    this.authController,
    this.actor,
    this.onLogout,
    this.controller,
  }) : assert(authController != null || actor != null);

  final AuthenticationController? authController;
  final UserProfile? actor;
  final Future<void> Function()? onLogout;
  final AcademicManagementController? controller;

  @override
  State<AcademicManagementArea> createState() => _AcademicManagementAreaState();
}

class _AcademicManagementAreaState extends State<AcademicManagementArea> {
  AcademicManagementController? controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    final actor = widget.actor ?? widget.authController?.state.profile;
    controller = widget.controller;
    if (controller == null && actor != null) {
      controller = AcademicManagementController(
        actor: actor,
        repository: FirestoreAcademicRepository(),
      );
    }
    controller?.load();
  }

  @override
  void dispose() {
    if (ownsController) controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentController = controller;
    if (currentController == null) {
      return const AppPageScaffold(
        title: 'Academic management',
        body: Center(
          child: AppStatePanel.error(
            title: 'Profile unavailable',
            message:
                'Your account profile could not be loaded. Please sign in again.',
          ),
        ),
      );
    }
    return AcademicManagementShell(
      controller: currentController,
      onLogout:
          widget.onLogout ?? widget.authController?.signOut ?? () async {},
    );
  }
}

class AcademicManagementShell extends StatefulWidget {
  const AcademicManagementShell({
    super.key,
    required this.controller,
    required this.onLogout,
  });
  final AcademicManagementController controller;
  final Future<void> Function() onLogout;

  @override
  State<AcademicManagementShell> createState() =>
      _AcademicManagementShellState();
}

class _AcademicManagementShellState extends State<AcademicManagementShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) {
      final teacher = widget.controller.actor.role == UserRole.teacher;
      final pages = <Widget>[
        AcademicDashboardScreen(controller: widget.controller),
        ClassListScreen(controller: widget.controller),
        if (!teacher)
          StudentListScreen(controller: widget.controller)
        else if (widget.controller.requestsTeacherStudentBackend)
          _TeacherUnavailableFeatureScreen(
            icon: Icons.people_outline,
            title: 'Assigned students',
            message:
                'Your student permission is enabled. A trusted redacted student service must be deployed before parent-contact records can be loaded safely.',
          ),
        if (teacher &&
            widget
                .controller
                .actor
                .effectiveTeacherPermissions
                .canTakeAttendance)
          _TeacherFeatureLauncher(
            icon: Icons.fact_check_outlined,
            title: 'Attendance',
            message: 'Open attendance for one of your assigned classes.',
            buttonLabel: 'Open attendance',
            onOpen: (context) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AttendanceManagementArea(
                  academicController: widget.controller,
                ),
              ),
            ),
          ),
        if (teacher &&
            widget
                .controller
                .actor
                .effectiveTeacherPermissions
                .canExportReports)
          _TeacherFeatureLauncher(
            icon: Icons.analytics_outlined,
            title: 'Reports',
            message:
                'Reports are limited to attendance loaded for assigned classes.',
            buttonLabel: 'Open reports',
            onOpen: (context) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AttendanceManagementArea(
                  academicController: widget.controller,
                ),
              ),
            ),
          ),
        if (teacher) _TeacherProfileScreen(actor: widget.controller.actor),
        if (!teacher) AcademicAuditLogScreen(controller: widget.controller),
      ];
      final destinations = <NavigationDestination>[
        const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Overview',
        ),
        const NavigationDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school_rounded),
          label: 'Classes',
        ),
        if (!teacher)
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Students',
          ),
        if (teacher && widget.controller.requestsTeacherStudentBackend)
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Students',
          ),
        if (teacher &&
            widget
                .controller
                .actor
                .effectiveTeacherPermissions
                .canTakeAttendance)
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Attendance',
          ),
        if (teacher &&
            widget
                .controller
                .actor
                .effectiveTeacherPermissions
                .canExportReports)
          const NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Reports',
          ),
        if (teacher)
          const NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle_rounded),
            label: 'Profile',
          ),
        if (!teacher)
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Audit',
          ),
      ];
      if (index >= pages.length) index = 0;
      return Scaffold(
        appBar: AppBar(
          title: Text(teacher ? 'Teacher workspace' : 'Academic management'),
          actions: [
            IconButton(
              onPressed: widget.controller.load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
            ),
          ],
        ),
        body: widget.controller.loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (widget.controller.error != null)
                    MaterialBanner(
                      content: Text(widget.controller.error!),
                      actions: [
                        TextButton(
                          onPressed: widget.controller.load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(index),
                        child: pages[index],
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: destinations,
        ),
      );
    },
  );
}

class _TeacherFeatureLauncher extends StatelessWidget {
  const _TeacherFeatureLauncher({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onOpen,
  });
  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      DashboardHeader(
        title: title,
        subtitle: message,
        icon: icon,
        eyebrow: 'Assigned work',
      ),
      const SizedBox(height: 18),
      FeatureActionCard(
        title: buttonLabel,
        subtitle: message,
        icon: icon,
        onTap: () => onOpen(context),
      ),
    ],
  );
}

class _TeacherUnavailableFeatureScreen extends StatelessWidget {
  const _TeacherUnavailableFeatureScreen({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      DashboardHeader(
        title: title,
        subtitle: 'Permission enabled with privacy protection.',
        icon: icon,
        eyebrow: 'Trusted service required',
      ),
      const SizedBox(height: 18),
      AppStatePanel(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Not configured',
        message: message,
      ),
    ],
  );
}

class _TeacherProfileScreen extends StatelessWidget {
  const _TeacherProfileScreen({required this.actor});
  final UserProfile actor;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      DashboardHeader(
        title: actor.displayName,
        subtitle: 'Teacher account and granted access',
        icon: Icons.account_circle_rounded,
        eyebrow: 'Profile',
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              DetailInformationRow(label: 'Email', value: actor.email),
              DetailInformationRow(
                label: 'Employee no.',
                value: actor.employeeNumber ?? 'Not provided',
              ),
              DetailInformationRow(
                label: 'Mobile',
                value: actor.phoneNumber ?? 'Not provided',
              ),
              DetailInformationRow(
                label: 'Institute',
                value: actor.instituteId ?? 'Not assigned',
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class AcademicDashboardScreen extends StatelessWidget {
  const AcademicDashboardScreen({super.key, required this.controller});
  final AcademicManagementController controller;

  @override
  Widget build(BuildContext context) {
    final actor = controller.actor;
    final teacher = actor.role == UserRole.teacher;
    final activeClasses = controller.classes
        .where((e) => e.status == AcademicClassStatus.active)
        .length;
    final activeStudents = controller.students.where((e) => e.active).length;
    final today = DateTime.now();
    final todayWeekday = ClassWeekday.values[today.weekday - 1];
    final todayClasses = controller.classes
        .where(
          (value) => value.active && value.daysOfWeek.contains(todayWeekday),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DashboardHeader(
          title: teacher
              ? 'Welcome, ${actor.displayName}'
              : 'Institute academic workspace',
          subtitle: teacher
              ? '$todayClasses classes scheduled today • ${_friendlyDate(today)}'
              : 'Classes, students, schedules and enrolments for your institute.',
          icon: teacher ? Icons.co_present_rounded : Icons.apartment_rounded,
          eyebrow: teacher ? 'Teacher workspace' : 'Full institute access',
        ),
        if (teacher) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your access',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TeacherPermission.values
                        .where(
                          controller.actor.effectiveTeacherPermissions.allows,
                        )
                        .map(
                          (permission) => Chip(
                            avatar: const Icon(Icons.check_rounded, size: 17),
                            label: Text(_academicPermissionLabel(permission)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'At a glance',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        OverviewMetricGrid(
          children: [
            StatisticCard(
              label: 'Active classes',
              value: '$activeClasses',
              icon: Icons.school,
            ),
            StatisticCard(
              label: teacher ? "Today's classes" : 'Students',
              value: teacher
                  ? '$todayClasses'
                  : '${controller.students.length}',
              icon: teacher ? Icons.today_outlined : Icons.people,
            ),
            if (!teacher)
              StatisticCard(
                label: 'Active students',
                value: '$activeStudents',
                icon: Icons.how_to_reg,
              ),
            if (!teacher)
              StatisticCard(
                label: 'Enrolments',
                value:
                    '${controller.assignments.where((e) => e.active).length}',
                icon: Icons.link,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Quick actions',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (controller.canCreateClass)
          FeatureActionCard(
            title: 'Create class',
            subtitle: teacher
                ? 'You will be assigned as the primary Teacher automatically.'
                : 'Create a class and assign its primary Teacher.',
            icon: Icons.add_business_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<AcademicClass>(
                builder: (_) => CreateClassScreen(controller: controller),
              ),
            ),
          ),
        if (controller.canCreateStudentDirectly)
          FeatureActionCard(
            title: 'Add student',
            subtitle: 'Create a protected institute student record.',
            icon: Icons.person_add_alt_1_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<Student>(
                builder: (_) => CreateStudentScreen(controller: controller),
              ),
            ),
          ),
        if (teacher && controller.requestsTeacherStudentBackend)
          FeatureActionCard(
            title: 'Students',
            subtitle: 'Permission enabled; trusted redacted service required.',
            icon: Icons.people_outline,
            badge: 'Not configured',
            onTap: () => _showNotConfigured(
              context,
              'Student access requires the trusted assigned-student service.',
            ),
          ),
        if (actor.role != UserRole.teacher ||
            actor.effectiveTeacherPermissions.canTakeAttendance)
          FeatureActionCard(
            title: 'Start attendance',
            subtitle: 'Select an assigned class and open continuous scanning.',
            icon: Icons.qr_code_scanner_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    AttendanceManagementArea(academicController: controller),
              ),
            ),
          ),
        if (actor.role == UserRole.teacher &&
            actor.effectiveTeacherPermissions.canSendManualNotifications)
          FeatureActionCard(
            title: 'Manual notifications',
            subtitle: 'Notification backend is not configured.',
            icon: Icons.notifications_active_outlined,
            badge: 'Not configured',
            onTap: () => _showNotConfigured(
              context,
              'Manual notifications will become available only after the reviewed notification backend is deployed.',
            ),
          ),
      ],
    );
  }
}

String _friendlyDate(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}

Future<void> _showNotConfigured(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('Not configured'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );

class ClassListScreen extends StatelessWidget {
  const ClassListScreen({super.key, required this.controller});
  final AcademicManagementController controller;

  @override
  Widget build(BuildContext context) {
    final canCreate = AcademicAuthorization.canCreateClasses(controller.actor);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final search = AppSearchBar(
              hint: 'Search name, code, subject, or grade',
              onChanged: controller.setClassSearch,
            );
            final filter = DropdownButtonFormField<AcademicClassFilter>(
              initialValue: controller.classFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              onChanged: (value) {
                if (value != null) controller.setClassFilter(value);
              },
              items: AcademicClassFilter.values
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                  .toList(),
            );
            if (constraints.maxWidth < 620) {
              return Column(
                children: [search, const SizedBox(height: 10), filter],
              );
            }
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: filter),
              ],
            );
          },
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            DropdownButton<String?>(
              value: controller.classTeacherFilter,
              hint: const Text('All teachers'),
              onChanged: controller.setClassTeacherFilter,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All teachers'),
                ),
                ...controller.teachers.map(
                  (e) => DropdownMenuItem<String?>(
                    value: e.uid,
                    child: Text(e.displayName),
                  ),
                ),
              ],
            ),
            DropdownButton<String?>(
              value: controller.classSubjectFilter,
              hint: const Text('All subjects'),
              onChanged: controller.setClassSubjectFilter,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All subjects'),
                ),
                ...controller.classes
                    .map((e) => e.subject)
                    .toSet()
                    .map(
                      (e) =>
                          DropdownMenuItem<String?>(value: e, child: Text(e)),
                    ),
              ],
            ),
            DropdownButton<String?>(
              value: controller.classGradeFilter,
              hint: const Text('All grades'),
              onChanged: controller.setClassGradeFilter,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All grades'),
                ),
                ...controller.classes
                    .map((e) => e.grade)
                    .whereType<String>()
                    .toSet()
                    .map(
                      (e) =>
                          DropdownMenuItem<String?>(value: e, child: Text(e)),
                    ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (canCreate)
          Align(
            alignment: Alignment.centerRight,
            child: _OpenCreateClassButton(controller: controller),
          ),
        if (controller.visibleClasses.isEmpty)
          const _EmptyState(
            icon: Icons.school_outlined,
            message: 'No classes match this search and filter.',
          ),
        for (final value in controller.visibleClasses)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                child: Text(
                  value.classCode.substring(
                    0,
                    value.classCode.length > 2 ? 2 : value.classCode.length,
                  ),
                ),
              ),
              title: Text(value.name),
              subtitle: Text(
                '${value.classCode} • ${value.subject} • ${value.scheduleLabel}',
              ),
              trailing: AppStatusChip(
                label: value.status.name,
                color: value.status == AcademicClassStatus.active
                    ? const Color(0xFF16A34A)
                    : value.status == AcademicClassStatus.archived
                    ? const Color(0xFF64748B)
                    : const Color(0xFFF59E0B),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClassDetailsScreen(
                    controller: controller,
                    academicClass: value,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OpenCreateClassButton extends StatefulWidget {
  const _OpenCreateClassButton({required this.controller});
  final AcademicManagementController controller;

  @override
  State<_OpenCreateClassButton> createState() => _OpenCreateClassButtonState();
}

class _OpenCreateClassButtonState extends State<_OpenCreateClassButton> {
  bool opening = false;

  Future<void> open() async {
    if (opening) return;
    setState(() => opening = true);
    widget.controller.clearError();
    try {
      final created = await Navigator.of(context).push<AcademicClass>(
        MaterialPageRoute<AcademicClass>(
          settings: const RouteSettings(name: 'academic/create-class'),
          builder: (_) => CreateClassScreen(controller: widget.controller),
        ),
      );
      if (created != null) {
        await widget.controller.refreshClasses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${created.name} was created.')),
          );
        }
      }
    } catch (exception) {
      if (kDebugMode) {
        debugPrint(
          '[AcademicNavigation] open create class failed type=${exception.runtimeType}',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open Create Class.')),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const Key('openCreateClassButton'),
    onPressed: opening ? null : open,
    icon: opening
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.add),
    label: Text(opening ? 'Opening…' : 'Create class'),
  );
}

class CreateClassScreen extends StatefulWidget {
  const CreateClassScreen({super.key, required this.controller});
  final AcademicManagementController controller;
  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  final name = TextEditingController();
  final subject = TextEditingController();
  final grade = TextEditingController();
  final room = TextEditingController();
  final year = TextEditingController(text: '${DateTime.now().year}');
  final start = TextEditingController(text: '08:00');
  final end = TextEditingController(text: '09:00');
  final days = <ClassWeekday>{ClassWeekday.monday};
  String? primaryTeacherId;

  @override
  void dispose() {
    for (final value in [code, name, subject, grade, room, year, start, end]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Create class')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Class code'),
              validator: ClassCodeValidator.validate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Class name'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Class name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: subject,
              decoration: const InputDecoration(labelText: 'Subject'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Subject is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: grade,
              decoration: const InputDecoration(labelText: 'Grade (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: start,
                    decoration: const InputDecoration(
                      labelText: 'Start (HH:mm)',
                    ),
                    validator: _timeValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: end,
                    decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                    validator: _timeValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: ClassWeekday.values
                  .map(
                    (day) => FilterChip(
                      label: Text(day.name.substring(0, 3)),
                      selected: days.contains(day),
                      onSelected: (selected) => setState(
                        () => selected ? days.add(day) : days.remove(day),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (days.isEmpty)
              const Text(
                'Select at least one day.',
                style: TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 12),
            if (widget.controller.actor.role == UserRole.teacher)
              const AppStatePanel(
                icon: Icons.assignment_ind_rounded,
                title: 'Automatic assignment',
                message:
                    'You will be assigned as the primary Teacher. You cannot select another institute or Teacher.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: primaryTeacherId,
                decoration: const InputDecoration(
                  labelText: 'Primary teacher (optional)',
                ),
                items: widget.controller.teachers
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.uid,
                        child: Text(e.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => primaryTeacherId = value),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: room,
              decoration: const InputDecoration(labelText: 'Room or location'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Academic year'),
              validator: (v) {
                final parsed = int.tryParse(v ?? '');
                if (parsed == null) return 'Enter a valid year';
                return parsed < 2000 || parsed > 2200
                    ? 'Use a year between 2000 and 2200'
                    : null;
              },
            ),
            const SizedBox(height: 20),
            if (widget.controller.error != null) ...[
              Semantics(
                liveRegion: true,
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.controller.error!,
                      key: const Key('createClassError'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('submitClassButton'),
              onPressed: widget.controller.saving ? null : _submit,
              child: widget.controller.saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create class'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (widget.controller.saving) return;
    widget.controller.clearError();
    if (!(formKey.currentState?.validate() ?? false) || days.isEmpty) {
      setState(() {});
      return;
    }
    final created = await widget.controller.createClass(
      code: code.text,
      name: name.text,
      subject: subject.text,
      grade: grade.text,
      start: LocalTime.tryParse(start.text)!,
      end: LocalTime.tryParse(end.text)!,
      days: days,
      room: room.text,
      academicYear: int.parse(year.text),
      teacherIds: primaryTeacherId == null ? const [] : [primaryTeacherId!],
      primaryTeacherId: primaryTeacherId,
    );
    if (!mounted) return;
    if (created != null) {
      Navigator.pop(context, created);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.error ?? 'The class could not be created.',
          ),
        ),
      );
    }
  }
}

String? _timeValidator(String? value) =>
    LocalTime.tryParse(value) == null ? 'Use 24-hour HH:mm' : null;

String _academicPermissionLabel(TeacherPermission value) => switch (value) {
  TeacherPermission.canCreateClasses => 'Create classes',
  TeacherPermission.canEditClasses => 'Edit classes',
  TeacherPermission.canAddStudents => 'Add students',
  TeacherPermission.canEditStudents => 'Edit students',
  TeacherPermission.canGenerateQrCodes => 'Generate QR',
  TeacherPermission.canTakeAttendance => 'Take attendance',
  TeacherPermission.canCorrectAttendance => 'Correct attendance',
  TeacherPermission.canExportReports => 'Export reports',
  TeacherPermission.canViewParentContacts => 'Parent contacts',
  TeacherPermission.canSendManualNotifications => 'Notifications',
};

class EditClassScreen extends StatefulWidget {
  const EditClassScreen({
    super.key,
    required this.controller,
    required this.academicClass,
  });
  final AcademicManagementController controller;
  final AcademicClass academicClass;
  @override
  State<EditClassScreen> createState() => _EditClassScreenState();
}

class _EditClassScreenState extends State<EditClassScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.academicClass.name,
  );
  late final TextEditingController subject = TextEditingController(
    text: widget.academicClass.subject,
  );
  late final TextEditingController grade = TextEditingController(
    text: widget.academicClass.grade,
  );
  late final TextEditingController description = TextEditingController(
    text: widget.academicClass.description,
  );
  late final TextEditingController room = TextEditingController(
    text: widget.academicClass.roomOrLocation,
  );
  late Set<String> teacherIds = widget.academicClass.teacherIds.toSet();
  late String? primaryTeacherId = widget.academicClass.primaryTeacherId;

  @override
  void dispose() {
    name.dispose();
    subject.dispose();
    grade.dispose();
    description.dispose();
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit class')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Class code ${widget.academicClass.classCode} is protected.'),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Class name'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: grade,
            decoration: const InputDecoration(labelText: 'Grade (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: room,
            decoration: const InputDecoration(labelText: 'Room or location'),
          ),
          const SizedBox(height: 16),
          if (widget.controller.canAssignTeachers(widget.academicClass)) ...[
            Text(
              'Teacher assignment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const AppStatePanel(
              icon: Icons.shield_outlined,
              title: 'Safe direct assignment',
              message:
                  'One primary Teacher can be assigned from the mobile app. Multiple-Teacher changes require the reviewed trusted transaction.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: primaryTeacherId,
              decoration: const InputDecoration(labelText: 'Primary teacher'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No Teacher assigned'),
                ),
                ...widget.controller.teachers.map(
                  (e) => DropdownMenuItem<String?>(
                    value: e.uid,
                    child: Text(e.displayName),
                  ),
                ),
              ],
              onChanged: (value) => setState(() {
                primaryTeacherId = value;
                teacherIds = value == null ? <String>{} : {value};
              }),
            ),
          ] else
            const AppStatePanel(
              icon: Icons.lock_outline_rounded,
              title: 'Teacher assignment protected',
              message:
                  'Only an Institute Admin can change the Teachers assigned to this class.',
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Save class changes'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final value = widget.academicClass.copyWith(
      name: name.text.trim(),
      subject: subject.text.trim(),
      grade: grade.text.trim(),
      clearGrade: grade.text.trim().isEmpty,
      description: description.text.trim(),
      roomOrLocation: room.text.trim(),
      teacherIds: teacherIds.toList(),
      primaryTeacherId: primaryTeacherId,
      clearPrimaryTeacher: primaryTeacherId == null,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: widget.controller.actor.uid,
    );
    if (await widget.controller.updateClass(value) && mounted) {
      Navigator.pop(context);
    }
  }
}

class ClassDetailsScreen extends StatelessWidget {
  const ClassDetailsScreen({
    super.key,
    required this.controller,
    required this.academicClass,
  });
  final AcademicManagementController controller;
  final AcademicClass academicClass;

  @override
  Widget build(BuildContext context) {
    final assigned = controller.assignments
        .where((e) => e.classId == academicClass.classId && e.active)
        .toList();
    final students = controller.students
        .where(
          (student) => assigned.any((e) => e.studentId == student.studentId),
        )
        .toList();
    final changes = controller.scheduleChanges
        .where((e) => e.classId == academicClass.classId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(academicClass.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    academicClass.classCode,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${academicClass.subject} • ${academicClass.grade ?? 'No grade'}',
                  ),
                  Text(academicClass.scheduleLabel),
                  Text(
                    'Room: ${academicClass.roomOrLocation.isEmpty ? 'Not set' : academicClass.roomOrLocation}',
                  ),
                  Text('Status: ${academicClass.status.name}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.canEditClass(academicClass)
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => EditClassScreen(
                            controller: controller,
                            academicClass: academicClass,
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit class'),
              ),
              OutlinedButton.icon(
                onPressed: controller.canChangeClassStatus(academicClass)
                    ? () => _changeStatus(context)
                    : null,
                icon: const Icon(Icons.edit),
                label: const Text('Edit status'),
              ),
              OutlinedButton.icon(
                onPressed:
                    AcademicAuthorization.canManageScheduleChange(
                      controller.actor,
                      academicClass,
                    )
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ClassScheduleChangeScreen(
                            controller: controller,
                            academicClass: academicClass,
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.event_repeat),
                label: const Text('Temporary schedule'),
              ),
              OutlinedButton.icon(
                onPressed: controller.canAssignStudents(academicClass)
                    ? () => _addStudent(context)
                    : null,
                icon: const Icon(Icons.person_add),
                label: const Text('Add students'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Enrolled students',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (students.isEmpty)
            const _EmptyState(
              icon: Icons.group_off,
              message: 'No students are enrolled in this class.',
            ),
          for (final student in students)
            ListTile(
              title: Text(student.fullName),
              subtitle: Text(student.studentNumber),
              trailing: controller.canAssignStudents(academicClass)
                  ? IconButton(
                      tooltip: 'Remove from class',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _removeStudent(context, student),
                    )
                  : null,
            ),
          const SizedBox(height: 20),
          Text(
            'Schedule history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (changes.isEmpty) const Text('No temporary schedule changes.'),
          for (final change in changes)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${change.effectiveDate.toLocal().toString().split(' ').first} • ${change.status.name}',
              ),
              subtitle: Text(
                '${change.newStartTime.wireValue}–${change.newEndTime.wireValue} • ${change.reason}',
              ),
              trailing:
                  change.status == ScheduleChangeStatus.scheduled &&
                      AcademicAuthorization.canManageScheduleChange(
                        controller.actor,
                        academicClass,
                      )
                  ? TextButton(
                      onPressed: () => controller.saveScheduleChange(
                        change.cancel(DateTime.now().toUtc()),
                      ),
                      child: const Text('Cancel change'),
                    )
                  : null,
            ),
          const SizedBox(height: 20),
          const Card(
            child: ListTile(
              leading: Icon(Icons.fact_check_outlined),
              title: Text('Attendance history'),
              subtitle: Text(
                'Open Attendance operations to scan, correct, and export records.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context) async {
    final next = await showDialog<AcademicClassStatus>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Select class status'),
        children: AcademicClassStatus.values
            .map(
              (status) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, status),
                child: Row(
                  children: [
                    Icon(
                      status == academicClass.status
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(status.name),
                          Text(
                            status == AcademicClassStatus.archived
                                ? 'Retains history and prevents normal Teacher editing.'
                                : status == AcademicClassStatus.active
                                ? 'Available for assignments and attendance.'
                                : 'Temporarily unavailable while retaining history.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (next == null || next == academicClass.status || !context.mounted) {
      return;
    }
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Change class status?',
      message: 'Historical class and enrolment data will be retained.',
      confirmLabel: 'Update status',
      destructive: next == AcademicClassStatus.archived,
    );
    if (confirmed) {
      final saved = await controller.updateClass(
        academicClass.copyWith(
          status: next,
          active: next == AcademicClassStatus.active,
          updatedAt: DateTime.now().toUtc(),
          updatedBy: controller.actor.uid,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Class status updated to ${next.name}.'
                  : controller.error ?? 'Class status could not be updated.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _addStudent(BuildContext context) async {
    final candidates = controller.students
        .where(
          (student) => !controller.assignments.any(
            (e) =>
                e.classId == academicClass.classId &&
                e.studentId == student.studentId &&
                e.active,
          ),
        )
        .toList();
    final selected = await showDialog<Student>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add a student'),
        children: candidates.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No eligible students available.'),
                ),
              ]
            : candidates
                  .map(
                    (student) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, student),
                      child: Text(
                        '${student.fullName} (${student.studentNumber})',
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    final overlaps = controller.overlapsFor(selected.studentId, academicClass);
    if (overlaps.isEmpty) {
      await controller.assignStudent(
        student: selected,
        academicClass: academicClass,
      );
      return;
    }
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Schedule overlap detected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This overlaps with ${overlaps.map((e) => controller.classes.where((c) => c.classId == e.secondClassId).firstOrNull?.name ?? e.secondClassId).join(', ')}. Confirm only with an approved reason.',
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Approval reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm overlap'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.assignStudent(
        student: selected,
        academicClass: academicClass,
        overlapConfirmed: true,
        overlapReason: reason.text,
      );
    }
    reason.dispose();
  }

  Future<void> _removeStudent(BuildContext context, Student student) async {
    final assignment = controller.assignments.firstWhere(
      (e) =>
          e.classId == academicClass.classId &&
          e.studentId == student.studentId &&
          e.active,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove student from class?'),
        content: Text(
          '${student.fullName} will be removed from this class. Historical data is retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeAssignment(assignment);
  }
}

class ClassScheduleChangeScreen extends StatefulWidget {
  const ClassScheduleChangeScreen({
    super.key,
    required this.controller,
    required this.academicClass,
  });
  final AcademicManagementController controller;
  final AcademicClass academicClass;
  @override
  State<ClassScheduleChangeScreen> createState() =>
      _ClassScheduleChangeScreenState();
}

class _ClassScheduleChangeScreenState extends State<ClassScheduleChangeScreen> {
  final formKey = GlobalKey<FormState>();
  final start = TextEditingController();
  final end = TextEditingController();
  final room = TextEditingController();
  final reason = TextEditingController();
  DateTime date = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    start.text = widget.academicClass.startTime.wireValue;
    end.text = widget.academicClass.endTime.wireValue;
    room.text = widget.academicClass.roomOrLocation;
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    room.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Temporary schedule change')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Effective date'),
            subtitle: Text(date.toLocal().toString().split(' ').first),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                initialDate: date,
              );
              if (picked != null) setState(() => date = picked);
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: start,
                  validator: _timeValidator,
                  decoration: const InputDecoration(labelText: 'New start'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: end,
                  validator: _timeValidator,
                  decoration: const InputDecoration(labelText: 'New end'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: room,
            decoration: const InputDecoration(labelText: 'New room/location'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Reason is required' : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Save schedule change'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now().toUtc();
    final value = ClassScheduleChange(
      scheduleChangeId: 'schedule-${now.microsecondsSinceEpoch}',
      instituteId: widget.academicClass.instituteId,
      classId: widget.academicClass.classId,
      effectiveDate: DateTime.utc(date.year, date.month, date.day),
      oldStartTime: widget.academicClass.startTime,
      oldEndTime: widget.academicClass.endTime,
      newStartTime: LocalTime.tryParse(start.text)!,
      newEndTime: LocalTime.tryParse(end.text)!,
      oldRoomOrLocation: widget.academicClass.roomOrLocation,
      newRoomOrLocation: room.text.trim(),
      reason: reason.text.trim(),
      status: ScheduleChangeStatus.scheduled,
      changedBy: widget.controller.actor.uid,
      changedAt: now,
      updatedAt: now,
    );
    if (await widget.controller.saveScheduleChange(value) && mounted) {
      Navigator.pop(context);
    }
  }
}

class StudentListScreen extends StatelessWidget {
  const StudentListScreen({super.key, required this.controller});
  final AcademicManagementController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TextField(
        onChanged: controller.setStudentSearch,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Search name, student number, or parent mobile',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        children: [
          DropdownButton<StudentStatus?>(
            value: controller.studentStatusFilter,
            hint: const Text('All statuses'),
            onChanged: controller.setStudentStatusFilter,
            items: [
              const DropdownMenuItem<StudentStatus?>(
                value: null,
                child: Text('All statuses'),
              ),
              ...StudentStatus.values.map(
                (e) => DropdownMenuItem<StudentStatus?>(
                  value: e,
                  child: Text(e.name),
                ),
              ),
            ],
          ),
          DropdownButton<String?>(
            value: controller.classStudentFilter,
            hint: const Text('All classes'),
            onChanged: controller.setClassStudentFilter,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All classes'),
              ),
              ...controller.classes.map(
                (e) => DropdownMenuItem<String?>(
                  value: e.classId,
                  child: Text(e.name),
                ),
              ),
            ],
          ),
        ],
      ),
      if (controller.canCreateStudentDirectly)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CreateStudentScreen(controller: controller),
              ),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('Create student'),
          ),
        ),
      if (controller.visibleStudents.isEmpty)
        const _EmptyState(
          icon: Icons.person_search,
          message: 'No students match this search and filter.',
        ),
      for (final student in controller.visibleStudents)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(student.fullName),
            subtitle: Text(
              '${student.studentNumber} • ${student.primaryParentMobile}',
            ),
            trailing: Chip(label: Text(student.status.name)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StudentDetailsScreen(
                  controller: controller,
                  student: student,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CreateStudentScreen extends StatefulWidget {
  const CreateStudentScreen({super.key, required this.controller});
  final AcademicManagementController controller;
  @override
  State<CreateStudentScreen> createState() => _CreateStudentScreenState();
}

class _CreateStudentScreenState extends State<CreateStudentScreen> {
  final formKey = GlobalKey<FormState>();
  final number = TextEditingController();
  final name = TextEditingController();
  final parent = TextEditingController();
  final mobile = TextEditingController();
  final secondParent = TextEditingController();
  final secondMobile = TextEditingController();
  final email = TextEditingController();
  final address = TextEditingController();
  @override
  void dispose() {
    for (final value in [
      number,
      name,
      parent,
      mobile,
      secondParent,
      secondMobile,
      email,
      address,
    ]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create student')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (_, _) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Student photographs are not collected.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: number,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Student number'),
              validator: StudentNumberValidator.validate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: parent,
              decoration: const InputDecoration(
                labelText: 'Primary parent/guardian name',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Primary parent mobile',
              ),
              validator: MobileNumberValidator.validatePrimary,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: secondParent,
              decoration: const InputDecoration(
                labelText: 'Secondary parent/guardian name (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: secondMobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Secondary mobile (optional)',
              ),
              validator: MobileNumberValidator.validateSecondary,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Parent email (optional)',
              ),
              validator: FieldValidators.optionalEmail,
            ),
            const SizedBox(height: 20),
            if (widget.controller.error != null) ...[
              Semantics(
                liveRegion: true,
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.controller.error!,
                      key: const Key('createStudentError'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('submitStudentButton'),
              onPressed: widget.controller.saving ? null : _submit,
              child: widget.controller.saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create student'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (widget.controller.saving) return;
    widget.controller.clearError();
    if (!(formKey.currentState?.validate() ?? false)) return;
    final student = await widget.controller.createStudent(
      studentNumber: number.text,
      fullName: name.text,
      primaryParentName: parent.text,
      primaryParentMobile: mobile.text,
      secondaryParentName: secondParent.text,
      secondaryParentMobile: secondMobile.text,
      parentEmail: email.text,
      address: address.text,
    );
    if (!mounted) return;
    if (student != null) {
      Navigator.pop(context, student);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.error ?? 'The student could not be created.',
          ),
        ),
      );
    }
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

class StudentDetailsScreen extends StatelessWidget {
  const StudentDetailsScreen({
    super.key,
    required this.controller,
    required this.student,
  });
  final AcademicManagementController controller;
  final Student student;
  @override
  Widget build(BuildContext context) {
    final enrolled = controller.assignments
        .where((e) => e.studentId == student.studentId && e.active)
        .map(
          (e) => controller.classes
              .where((c) => c.classId == e.classId)
              .firstOrNull,
        )
        .whereType<AcademicClass>()
        .toList();
    final canSeeContacts = AcademicAuthorization.canViewParentContacts(
      controller.actor,
      student,
    );
    return Scaffold(
      appBar: AppBar(title: Text(student.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.studentNumber,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('Status: ${student.status.name}'),
                  Text(
                    'QR: ${student.qrEnabled ? 'enabled' : 'disabled'} • version ${student.qrVersion}',
                  ),
                ],
              ),
            ),
          ),
          if (canSeeContacts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.contact_phone),
                title: Text(student.primaryParentName),
                subtitle: Text(
                  '${student.primaryParentMobile}${student.parentEmail == null ? '' : '\n${student.parentEmail}'}',
                ),
              ),
            ),
          Text('Classes', style: Theme.of(context).textTheme.titleLarge),
          if (enrolled.isEmpty) const Text('Not assigned to a class.'),
          for (final value in enrolled)
            ListTile(
              title: Text(value.name),
              subtitle: Text(value.scheduleLabel),
            ),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('Attendance history placeholder'),
              subtitle: Text('Records become available after Milestone B.'),
            ),
          ),
          if (controller.canEditStudent(student))
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit student details'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditStudentScreen(
                    controller: controller,
                    student: student,
                  ),
                ),
              ),
            ),
          if (controller.canEditStudent(student))
            OutlinedButton.icon(
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Change student status'),
              onPressed: () => _toggle(context),
            ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final status = await showDialog<StudentStatus>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Select student status'),
        children: StudentStatus.values
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value),
                child: Row(
                  children: [
                    Icon(
                      value == student.status
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    const SizedBox(width: 12),
                    Text(value.name),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (status == null || status == student.status || !context.mounted) return;
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Change student status?',
      message: 'The student record and history will be retained.',
      confirmLabel: 'Update status',
      destructive:
          status == StudentStatus.suspended ||
          status == StudentStatus.leftInstitute,
    );
    if (confirmed) {
      final saved = await controller.updateStudent(
        student.copyWith(
          active: status == StudentStatus.active,
          status: status,
          updatedAt: DateTime.now().toUtc(),
          updatedBy: controller.actor.uid,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Student status updated to ${status.name}.'
                  : controller.error ?? 'Student status could not be updated.',
            ),
          ),
        );
      }
    }
  }
}

class EditStudentScreen extends StatefulWidget {
  const EditStudentScreen({
    super.key,
    required this.controller,
    required this.student,
  });
  final AcademicManagementController controller;
  final Student student;
  @override
  State<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.student.fullName,
  );
  late final TextEditingController parent = TextEditingController(
    text: widget.student.primaryParentName,
  );
  late final TextEditingController mobile = TextEditingController(
    text: widget.student.primaryParentMobile,
  );
  late final TextEditingController email = TextEditingController(
    text: widget.student.parentEmail,
  );
  late final TextEditingController address = TextEditingController(
    text: widget.student.address,
  );
  @override
  void dispose() {
    name.dispose();
    parent.dispose();
    mobile.dispose();
    email.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit student')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Student number ${widget.student.studentNumber} and QR security fields are protected.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: address,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: parent,
            decoration: const InputDecoration(
              labelText: 'Primary parent/guardian',
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Primary mobile'),
            validator: MobileNumberValidator.validatePrimary,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Parent email (optional)',
            ),
            validator: FieldValidators.optionalEmail,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Save student changes'),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final value = widget.student.copyWith(
      fullName: name.text.trim(),
      address: address.text.trim(),
      primaryParentName: parent.text.trim(),
      primaryParentMobile: MobileNumberValidator.normalize(mobile.text),
      parentEmail: email.text.trim().toLowerCase(),
      clearParentEmail: email.text.trim().isEmpty,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: widget.controller.actor.uid,
    );
    if (await widget.controller.updateStudent(value) && mounted) {
      Navigator.pop(context);
    }
  }
}

class AcademicAuditLogScreen extends StatelessWidget {
  const AcademicAuditLogScreen({super.key, required this.controller});
  final AcademicManagementController controller;
  @override
  Widget build(BuildContext context) {
    final entries = controller.auditLogs
        .where(
          (e) => const {
            AuditTargetType.academicClass,
            AuditTargetType.student,
            AuditTargetType.classStudentAssignment,
            AuditTargetType.scheduleChange,
          }.contains(e.targetType),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Academic audit log',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (entries.isEmpty)
          const _EmptyState(
            icon: Icons.history_toggle_off,
            message: 'No academic audit entries yet.',
          ),
        for (final entry in entries)
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(entry.action.name),
            subtitle: Text('${entry.summary}\n${entry.createdAt.toLocal()}'),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
