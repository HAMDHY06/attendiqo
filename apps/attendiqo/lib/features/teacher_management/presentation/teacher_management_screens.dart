import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../../academic_management/application/academic_management_controller.dart';
import '../../academic_management/data/firestore_academic_repository.dart';
import '../../academic_management/presentation/academic_management_screens.dart';
import '../../attendance/presentation/attendance_screens.dart';
import '../../password_recovery/data/firebase_managed_password_reset_service.dart';
import '../../../routing/app_router.dart';
import '../application/teacher_management_controller.dart';
import '../data/firestore_teacher_repository.dart';

const Listenable _noopListenable = _StaticListenable();

class _StaticListenable implements Listenable {
  const _StaticListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class TeacherManagementArea extends StatefulWidget {
  const TeacherManagementArea({
    super.key,
    required this.authController,
    this.controller,
    this.academicController,
  });

  final AuthenticationController authController;
  final TeacherManagementController? controller;
  final AcademicManagementController? academicController;

  @override
  State<TeacherManagementArea> createState() => _TeacherManagementAreaState();
}

class _TeacherManagementAreaState extends State<TeacherManagementArea> {
  late final TeacherManagementController controller;
  late final bool ownsController;
  AcademicManagementController? academicController;
  bool ownsAcademicController = false;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        TeacherManagementController(
          actor: widget.authController.state.profile!,
          repository: FirestoreTeacherRepository(),
          provisioningService: kDebugMode
              ? MockTeacherProvisioningService()
              : const UnavailableTeacherProvisioningService(),
          passwordResetService: FirebaseManagedPasswordResetService(),
          verifiedSuperAdminClaim:
              widget.authController.state.profile!.role == UserRole.superAdmin,
        );
    academicController = widget.academicController;
    if (academicController == null &&
        widget.controller == null &&
        controller.actor.role == UserRole.instituteAdmin) {
      ownsAcademicController = true;
      academicController = AcademicManagementController(
        actor: controller.actor,
        repository: FirestoreAcademicRepository(),
      );
    }
    controller.load();
    academicController?.load();
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    if (ownsAcademicController) academicController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TeacherDashboardScreen(
    controller: controller,
    academicController: academicController,
    onLogout: widget.authController.signOut,
  );
}

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({
    super.key,
    required this.controller,
    required this.onLogout,
    this.academicController,
  });

  final TeacherManagementController controller;
  final Future<void> Function() onLogout;
  final AcademicManagementController? academicController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: academicController == null
        ? controller
        : Listenable.merge([controller, academicController!]),
    builder: (_, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          controller.actor.role == UserRole.superAdmin
              ? 'Teacher monitoring'
              : 'Teacher Management',
        ),
        actions: [
          if (controller.actor.role == UserRole.instituteAdmin)
            IconButton(
              onPressed: () => _openAcademic(context),
              icon: const Icon(Icons.school_outlined),
              tooltip: 'Classes and students',
            ),
          IconButton(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
          ),
        ],
      ),
      floatingActionButton: controller.actor.role == UserRole.instituteAdmin
          ? FloatingActionButton.extended(
              key: const Key('createTeacherFab'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreateTeacherScreen(controller: controller),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create teacher'),
            )
          : null,
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DashboardHeader(
                    title: controller.actor.role == UserRole.superAdmin
                        ? 'Teacher monitoring'
                        : 'Welcome, ${controller.actor.displayName}',
                    subtitle: controller.actor.role == UserRole.superAdmin
                        ? 'Review Teacher access across institutes.'
                        : '${controller.actor.instituteId ?? 'Institute'} • ${_dashboardDate(DateTime.now())}',
                    icon: Icons.admin_panel_settings_rounded,
                    eyebrow: controller.actor.role == UserRole.superAdmin
                        ? 'Verified Super Admin'
                        : 'Full institute administration',
                  ),
                  if (controller.actor.role == UserRole.instituteAdmin) ...[
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AppStatusChip(
                        label: 'Full admin access',
                        color: Color(0xFF4338CA),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can create and edit institute classes, manage students, attendance and Teacher access. Teacher switches never limit your Institute Admin account.',
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Institute overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OverviewMetricGrid(
                      children: [
                        StatisticCard(
                          label: 'Total teachers',
                          value: '${controller.teachers.length}',
                          icon: Icons.groups_outlined,
                        ),
                        StatisticCard(
                          label: 'Active teachers',
                          value: '${controller.activeCount}',
                          icon: Icons.verified_user_outlined,
                          color: const Color(0xFF16A34A),
                        ),
                        StatisticCard(
                          label: 'Total classes',
                          value: '${academicController?.classes.length ?? 0}',
                          icon: Icons.school_outlined,
                        ),
                        StatisticCard(
                          label: 'Active classes',
                          value:
                              '${academicController?.classes.where((value) => value.status == AcademicClassStatus.active).length ?? 0}',
                          icon: Icons.event_available_outlined,
                          color: const Color(0xFF06B6D4),
                        ),
                        StatisticCard(
                          label: 'Total students',
                          value: '${academicController?.students.length ?? 0}',
                          icon: Icons.people_alt_outlined,
                        ),
                        const StatisticCard(
                          label: "Today's sessions",
                          value: '—',
                          icon: Icons.fact_check_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Quick actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _AdminQuickActions(
                      onAddTeacher: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CreateTeacherScreen(controller: controller),
                        ),
                      ),
                      onCreateClass: academicController == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<AcademicClass>(
                                builder: (_) => CreateClassScreen(
                                  controller: academicController!,
                                ),
                              ),
                            ),
                      onAddStudent: academicController == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<Student>(
                                builder: (_) => CreateStudentScreen(
                                  controller: academicController!,
                                ),
                              ),
                            ),
                      onAcademic: () => _openAcademic(context),
                      onAttendance: academicController == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AttendanceManagementArea(
                                  academicController: academicController!,
                                ),
                              ),
                            ),
                      onAudit: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TeacherAuditLogScreen(controller: controller),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Teacher overview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OverviewMetricGrid(
                    children: [
                      _MetricCard(
                        label: 'All teachers',
                        value: controller.teachers.length,
                        icon: Icons.groups_outlined,
                      ),
                      _MetricCard(
                        label: 'Active',
                        value: controller.activeCount,
                        icon: Icons.check_circle_outline,
                      ),
                      _MetricCard(
                        label: 'Pending first login',
                        value: controller.pendingCount,
                        icon: Icons.password_outlined,
                      ),
                      _MetricCard(
                        label: 'Disabled',
                        value: controller.disabledCount,
                        icon: Icons.block_outlined,
                      ),
                    ],
                  ),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                controller.error!,
                                key: const Key('teacherManagementError'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('teacherSearch'),
                    onChanged: controller.setSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search name, email or employee number',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: TeacherFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(_filterLabel(filter)),
                                selected: controller.filter == filter,
                                onSelected: (_) => controller.setFilter(filter),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (controller.actor.role == UserRole.superAdmin &&
                      controller.instituteIds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: controller.superAdminInstituteFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filter by institute ID',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          child: Text('All institutes'),
                        ),
                        ...controller.instituteIds.map(
                          (id) => DropdownMenuItem<String?>(
                            value: id,
                            child: Text(id),
                          ),
                        ),
                      ],
                      onChanged: controller.setInstituteFilter,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Teachers',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TeacherAuditLogScreen(controller: controller),
                          ),
                        ),
                        icon: const Icon(Icons.history),
                        label: const Text('Audit logs'),
                      ),
                    ],
                  ),
                  if (controller.visibleTeachers.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.person_search_outlined),
                        title: Text('No teachers found'),
                        subtitle: Text(
                          'Create a teacher or change the current search and filters.',
                        ),
                      ),
                    )
                  else
                    ...controller.visibleTeachers.map(
                      (teacher) => TeacherListCard(
                        teacher: teacher,
                        canEdit: controller.canEditTeacher(teacher),
                        updateInProgress: controller.saving,
                        onEdit: () async {
                          await Navigator.push<UserProfile>(
                            context,
                            MaterialPageRoute<UserProfile>(
                              builder: (_) => EditTeacherScreen(
                                controller: controller,
                                teacher: teacher,
                              ),
                            ),
                          );
                        },
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
                  const SizedBox(height: 88),
                ],
              ),
            ),
    ),
  );

  Future<void> _refresh() async {
    await Future.wait([
      controller.load(),
      if (academicController != null) academicController!.load(),
    ]);
  }

  void _openAcademic(BuildContext context) {
    final academic = academicController;
    if (academic == null) {
      Navigator.pushNamed(context, AppRoutes.academicManagement);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            AcademicManagementShell(controller: academic, onLogout: onLogout),
      ),
    );
  }

  static String _filterLabel(TeacherFilter value) => switch (value) {
    TeacherFilter.all => 'All',
    TeacherFilter.active => 'Active',
    TeacherFilter.disabled => 'Disabled',
    TeacherFilter.pendingFirstLogin => 'Pending first login',
  };
}

String _dashboardDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

class _AdminQuickActions extends StatelessWidget {
  const _AdminQuickActions({
    required this.onAddTeacher,
    required this.onCreateClass,
    required this.onAddStudent,
    required this.onAcademic,
    required this.onAttendance,
    required this.onAudit,
  });
  final VoidCallback onAddTeacher;
  final VoidCallback? onCreateClass;
  final VoidCallback? onAddStudent;
  final VoidCallback onAcademic;
  final VoidCallback? onAttendance;
  final VoidCallback onAudit;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      FeatureActionCard(
        title: 'Add Teacher',
        subtitle: 'Provision a Teacher account securely.',
        icon: Icons.person_add_alt_1_rounded,
        onTap: onAddTeacher,
      ),
      FeatureActionCard(
        title: 'Create Class',
        subtitle: 'Create and assign an institute class.',
        icon: Icons.add_business_rounded,
        onTap: onCreateClass,
      ),
      FeatureActionCard(
        title: 'Add Student',
        subtitle: 'Create a protected student record.',
        icon: Icons.person_add_rounded,
        onTap: onAddStudent,
      ),
      FeatureActionCard(
        title: 'Assign Student',
        subtitle: 'Open classes, students and enrolments.',
        icon: Icons.link_rounded,
        onTap: onAcademic,
      ),
      FeatureActionCard(
        title: 'Start Attendance',
        subtitle: 'Open secure attendance operations.',
        icon: Icons.fact_check_rounded,
        onTap: onAttendance,
      ),
      FeatureActionCard(
        title: 'Audit Logs',
        subtitle: 'Review recent institute activity.',
        icon: Icons.history_rounded,
        onTap: onAudit,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: actions
              .map((action) => SizedBox(width: width, child: action))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    ),
  );
}

class TeacherListCard extends StatelessWidget {
  const TeacherListCard({
    super.key,
    required this.teacher,
    required this.onTap,
    required this.canEdit,
    required this.updateInProgress,
    required this.onEdit,
  });
  final UserProfile teacher;
  final VoidCallback onTap;
  final bool canEdit;
  final bool updateInProgress;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(teacher.displayName),
      subtitle: Text(
        [
          teacher.email,
          'Employee: ${teacher.employeeNumber ?? 'Not assigned'} • Status: ${_statusLabel(teacher.effectiveTeacherStatus!)}',
          'Last login: ${_dateTime(teacher.lastLoginAt)}',
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: canEdit
          ? IconButton(
              key: Key('edit-teacher-${teacher.uid}'),
              visualDensity: VisualDensity.compact,
              onPressed: updateInProgress ? null : onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit teacher',
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class CreateTeacherScreen extends StatefulWidget {
  const CreateTeacherScreen({super.key, required this.controller});
  final TeacherManagementController controller;

  @override
  State<CreateTeacherScreen> createState() => _CreateTeacherScreenState();
}

class _CreateTeacherScreenState extends State<CreateTeacherScreen> {
  final formKey = GlobalKey<FormState>();
  final displayName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final employeeNumber = TextEditingController();
  TeacherPermissions permissions = const TeacherPermissions();

  @override
  void dispose() {
    displayName.dispose();
    email.dispose();
    phone.dispose();
    employeeNumber.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final result = await widget.controller.createTeacher(
      displayName: displayName.text,
      email: email.text,
      phoneNumber: phone.text,
      employeeNumber: employeeNumber.text,
      permissions: permissions,
    );
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.error ?? 'Unable to create the teacher.',
          ),
        ),
      );
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TemporaryPasswordResultScreen(result: result),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Create teacher')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              key: const Key('teacherDisplayName'),
              controller: displayName,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (value) =>
                  FieldValidators.required(value, label: 'Display name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('teacherEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: FieldValidators.email,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional)',
              ),
              validator: MobileNumberValidator.validateSecondary,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('teacherEmployeeNumber'),
              controller: employeeNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Employee number (optional)',
              ),
              validator: EmployeeNumberValidator.validateOptional,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await Navigator.push<TeacherPermissions>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TeacherPermissionsScreen(initial: permissions),
                  ),
                );
                if (selected != null) setState(() => permissions = selected);
              },
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Configure permissions'),
            ),
            const SizedBox(height: 12),
            const Text(
              'New teachers are active, pending first login, and must replace the temporary password. Development builds use a local mock until the trusted backend is deployed.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('submitTeacher'),
              onPressed: widget.controller.saving ? null : submit,
              child: widget.controller.saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create teacher securely'),
            ),
          ],
        ),
      ),
    ),
  );
}

class TemporaryPasswordResultScreen extends StatelessWidget {
  const TemporaryPasswordResultScreen({super.key, required this.result});
  final TeacherCreationResult result;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Teacher created'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.password, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      result.profile.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Copy this temporary password now. It is shown only once and is not stored in Firestore or audit logs.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      result.oneTimeTemporaryPassword,
                      key: const Key('teacherTemporaryPassword'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'If it is lost, use Send Password Reset Email. Do not recreate the account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('temporaryPasswordSaved'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('I saved it securely'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TeacherDetailsScreen extends StatefulWidget {
  const TeacherDetailsScreen({
    super.key,
    required this.controller,
    required this.initialTeacher,
  });
  final TeacherManagementController controller;
  final UserProfile initialTeacher;

  @override
  State<TeacherDetailsScreen> createState() => _TeacherDetailsScreenState();
}

class _TeacherDetailsScreenState extends State<TeacherDetailsScreen> {
  late UserProfile teacher = widget.initialTeacher;

  bool get canEdit => widget.controller.canEditTeacher(teacher);

  Future<void> disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disable teacher?'),
        content: const Text(
          'The teacher will lose access until the account is reactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDisableTeacher'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await widget.controller.setActive(teacher, false) && mounted) {
      setState(() {
        teacher = teacher.copyWithTeacher(
          active: false,
          teacherStatus: TeacherStatus.disabled,
        );
      });
    } else if (mounted && widget.controller.error != null) {
      _showError(widget.controller.error!);
    }
  }

  Future<void> reactivate() async {
    if (await widget.controller.setActive(teacher, true) && mounted) {
      setState(() {
        teacher = teacher.copyWithTeacher(
          active: true,
          teacherStatus: teacher.mustChangePassword
              ? TeacherStatus.pendingFirstLogin
              : TeacherStatus.active,
        );
      });
    } else if (mounted && widget.controller.error != null) {
      _showError(widget.controller.error!);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(teacher.displayName),
        actions: [
          if (canEdit)
            IconButton(
              key: Key('edit-teacher-detail-${teacher.uid}'),
              onPressed: widget.controller.saving
                  ? null
                  : () async {
                      final updated = await Navigator.push<UserProfile>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditTeacherScreen(
                            controller: widget.controller,
                            teacher: teacher,
                          ),
                        ),
                      );
                      if (updated != null) setState(() => teacher = updated);
                    },
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit teacher',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          teacher.displayName,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      _TeacherStatusBadge(
                        status: teacher.effectiveTeacherStatus!,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(teacher.email),
                  Text('Institute: ${teacher.instituteId}'),
                  Text('Employee: ${teacher.employeeNumber ?? 'Not assigned'}'),
                  Text('Phone: ${teacher.phoneNumber ?? 'Not provided'}'),
                  Text('Last login: ${_dateTime(teacher.lastLoginAt)}'),
                  Text(
                    teacher.mustChangePassword
                        ? 'First-login password change pending'
                        : 'First-login password change completed',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.controller.error != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.controller.error!),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (teacher.active)
                OutlinedButton.icon(
                  onPressed: canEdit && !widget.controller.saving
                      ? disable
                      : null,
                  icon: const Icon(Icons.block),
                  label: const Text('Disable teacher'),
                )
              else
                FilledButton.icon(
                  onPressed: canEdit && !widget.controller.saving
                      ? reactivate
                      : null,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reactivate teacher'),
                ),
              OutlinedButton.icon(
                onPressed:
                    !canEdit || widget.controller.resettingUid == teacher.uid
                    ? null
                    : () async {
                        final result = await widget.controller
                            .sendPasswordReset(teacher);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        }
                      },
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Send Password Reset Email'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Teacher permissions'),
                  subtitle: Text(
                    '${TeacherPermission.values.where(teacher.effectiveTeacherPermissions.allows).length} enabled',
                  ),
                  trailing: canEdit ? const Icon(Icons.chevron_right) : null,
                  onTap: !canEdit || widget.controller.saving
                      ? null
                      : () async {
                          final permissions =
                              await Navigator.push<TeacherPermissions>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeacherPermissionsScreen(
                                    initial:
                                        teacher.effectiveTeacherPermissions,
                                    controller: widget.controller,
                                    teacher: teacher,
                                  ),
                                ),
                              );
                          if (permissions == null) return;
                          final updated = teacher.copyWithTeacher(
                            permissions: permissions,
                          );
                          if (mounted) setState(() => teacher = updated);
                        },
                ),
                const Divider(height: 1),
                ExpansionTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Assigned permissions'),
                  children: TeacherPermission.values
                      .map(
                        (permission) => ListTile(
                          dense: true,
                          leading: Icon(
                            teacher.effectiveTeacherPermissions.allows(
                                  permission,
                                )
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                          ),
                          title: Text(_permissionLabel(permission)),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 1),
                ExpansionTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Assigned classes'),
                  subtitle: Text(
                    widget
                                .controller
                                .assignedClassNames[teacher.uid]
                                ?.isNotEmpty ==
                            true
                        ? '${widget.controller.assignedClassNames[teacher.uid]!.length} assigned'
                        : 'No assigned classes',
                  ),
                  children:
                      (widget.controller.assignedClassNames[teacher.uid] ??
                              const <String>[])
                          .map(
                            (name) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.class_outlined),
                              title: Text(name),
                            ),
                          )
                          .toList(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Teacher audit logs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TeacherAuditLogScreen(
                        controller: widget.controller,
                        teacherUid: teacher.uid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EditTeacherScreen extends StatefulWidget {
  const EditTeacherScreen({
    super.key,
    required this.controller,
    required this.teacher,
  });
  final TeacherManagementController controller;
  final UserProfile teacher;

  @override
  State<EditTeacherScreen> createState() => _EditTeacherScreenState();
}

class _EditTeacherScreenState extends State<EditTeacherScreen> {
  final formKey = GlobalKey<FormState>();
  late final displayName = TextEditingController(
    text: widget.teacher.displayName,
  );
  late final phone = TextEditingController(text: widget.teacher.phoneNumber);
  late final employee = TextEditingController(
    text: widget.teacher.employeeNumber,
  );

  @override
  void dispose() {
    displayName.dispose();
    phone.dispose();
    employee.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final updated = widget.teacher.copyWithTeacher(
      displayName: displayName.text.trim(),
      phoneNumber: phone.text.trim(),
      clearPhoneNumber: phone.text.trim().isEmpty,
      employeeNumber: EmployeeNumberValidator.normalize(employee.text),
      clearEmployeeNumber: employee.text.trim().isEmpty,
    );
    if (await widget.controller.saveTeacher(updated) && mounted) {
      Navigator.pop(context, updated);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit teacher')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: displayName,
            decoration: const InputDecoration(labelText: 'Display name'),
            validator: (value) =>
                FieldValidators.required(value, label: 'Display name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: widget.teacher.email,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              helperText:
                  'Authentication email changes require a trusted backend.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phone,
            decoration: const InputDecoration(
              labelText: 'Phone number (optional)',
            ),
            validator: MobileNumberValidator.validateSecondary,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: employee,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Employee number (optional)',
            ),
            validator: EmployeeNumberValidator.validateOptional,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.controller.saving ? null : submit,
            child: const Text('Save teacher'),
          ),
        ],
      ),
    ),
  );
}

class TeacherPermissionsScreen extends StatefulWidget {
  const TeacherPermissionsScreen({
    super.key,
    required this.initial,
    this.controller,
    this.teacher,
  }) : assert((controller == null) == (teacher == null));
  final TeacherPermissions initial;
  final TeacherManagementController? controller;
  final UserProfile? teacher;

  @override
  State<TeacherPermissionsScreen> createState() =>
      _TeacherPermissionsScreenState();
}

class _TeacherPermissionsScreenState extends State<TeacherPermissionsScreen> {
  late TeacherPermissions value = widget.initial;
  late TeacherPermissions saved = widget.initial;

  bool get changed => value != saved;

  Future<void> save() async {
    if (!changed || widget.controller?.saving == true) return;
    final controller = widget.controller;
    if (controller != null) {
      final updated = await controller.updateTeacherPermissions(
        widget.teacher!,
        value,
      );
      if (!mounted) return;
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.error ?? 'Unable to save teacher permissions.',
            ),
          ),
        );
        return;
      }
    }
    saved = value;
    if (mounted) Navigator.pop(context, value);
  }

  Future<void> confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your permission changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('discardPermissionChanges'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller ?? _noopListenable,
    builder: (context, _) => PopScope<TeacherPermissions>(
      canPop: !changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Teacher permissions')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEEF2FF), Color(0xFFECFEFF)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Institute Admin accounts already have full institute access. These controls define what this teacher can do.',
                      style: TextStyle(
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Quick presets',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('permissionPresetFullAccess'),
                  onPressed: () =>
                      setState(() => value = TeacherPermissions.fullAccess),
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('Full access'),
                ),
                OutlinedButton.icon(
                  key: const Key('permissionPresetAttendance'),
                  onPressed: () => setState(
                    () => value = TeacherPermissions.attendanceAccess,
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Attendance only'),
                ),
                OutlinedButton.icon(
                  key: const Key('permissionPresetRecommended'),
                  onPressed: () =>
                      setState(() => value = const TeacherPermissions()),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Recommended'),
                ),
                TextButton.icon(
                  key: const Key('permissionPresetClear'),
                  onPressed: () =>
                      setState(() => value = TeacherPermissions.noAccess),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _PermissionSection(
              title: 'Classes and students',
              icon: Icons.school_rounded,
              permissions: const [
                TeacherPermission.canCreateClasses,
                TeacherPermission.canEditClasses,
                TeacherPermission.canAddStudents,
                TeacherPermission.canEditStudents,
                TeacherPermission.canGenerateQrCodes,
                TeacherPermission.canViewParentContacts,
              ],
              value: value,
              onChanged: (permission, enabled) => setState(
                () => value = _withPermission(value, permission, enabled),
              ),
            ),
            const SizedBox(height: 12),
            _PermissionSection(
              title: 'Attendance and reports',
              icon: Icons.fact_check_rounded,
              permissions: const [
                TeacherPermission.canTakeAttendance,
                TeacherPermission.canCorrectAttendance,
                TeacherPermission.canExportReports,
              ],
              value: value,
              onChanged: (permission, enabled) => setState(
                () => value = _withPermission(value, permission, enabled),
              ),
            ),
            const SizedBox(height: 12),
            _PermissionSection(
              title: 'Communication',
              icon: Icons.notifications_active_outlined,
              permissions: const [TeacherPermission.canSendManualNotifications],
              value: value,
              onChanged: (permission, enabled) => setState(
                () => value = _withPermission(value, permission, enabled),
              ),
            ),
            const SizedBox(height: 16),
            if (changed)
              const ListTile(
                key: Key('unsavedPermissionChanges'),
                leading: Icon(Icons.edit_note),
                title: Text('Unsaved changes'),
                subtitle: Text('Review the switches, then save them together.'),
              ),
            if (widget.controller?.error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(widget.controller!.error!),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('savePermissionChanges'),
              onPressed: !changed || widget.controller?.saving == true
                  ? null
                  : save,
              child: widget.controller?.saving == true
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.icon,
    required this.permissions,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<TeacherPermission> permissions;
  final TeacherPermissions value;
  final void Function(TeacherPermission permission, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        ListTile(
          leading: CircleAvatar(child: Icon(icon, size: 20)),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        for (var index = 0; index < permissions.length; index++) ...[
          SwitchListTile(
            key: Key('permission-${permissions[index].name}'),
            title: Text(_permissionLabel(permissions[index])),
            subtitle: Text(_permissionDescription(permissions[index])),
            value: value.allows(permissions[index]),
            onChanged: (enabled) => onChanged(permissions[index], enabled),
          ),
          if (index != permissions.length - 1) const Divider(height: 1),
        ],
      ],
    ),
  );
}

class TeacherAuditLogScreen extends StatelessWidget {
  const TeacherAuditLogScreen({
    super.key,
    required this.controller,
    this.teacherUid,
  });
  final TeacherManagementController controller;
  final String? teacherUid;

  @override
  Widget build(BuildContext context) {
    final logs = teacherUid == null
        ? controller.auditLogs
        : controller.auditLogsFor(teacherUid!);
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher audit logs')),
      body: logs.isEmpty
          ? const Center(child: Text('No teacher audit entries found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, index) {
                final log = logs[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_auditLabel(log.action)),
                  subtitle: Text(log.summary),
                  trailing: Text(_dateTime(log.createdAt)),
                );
              },
            ),
    );
  }
}

class _TeacherStatusBadge extends StatelessWidget {
  const _TeacherStatusBadge({required this.status});
  final TeacherStatus status;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    avatar: Icon(
      status == TeacherStatus.active
          ? Icons.check_circle
          : status == TeacherStatus.disabled
          ? Icons.block
          : Icons.password,
      size: 18,
    ),
    label: Text(switch (status) {
      TeacherStatus.active => 'Active',
      TeacherStatus.disabled => 'Disabled',
      TeacherStatus.pendingFirstLogin => 'Pending login',
    }),
  );
}

TeacherPermissions _withPermission(
  TeacherPermissions value,
  TeacherPermission permission,
  bool enabled,
) => switch (permission) {
  TeacherPermission.canCreateClasses => value.copyWith(
    canCreateClasses: enabled,
  ),
  TeacherPermission.canEditClasses => value.copyWith(canEditClasses: enabled),
  TeacherPermission.canAddStudents => value.copyWith(canAddStudents: enabled),
  TeacherPermission.canEditStudents => value.copyWith(canEditStudents: enabled),
  TeacherPermission.canGenerateQrCodes => value.copyWith(
    canGenerateQrCodes: enabled,
  ),
  TeacherPermission.canTakeAttendance => value.copyWith(
    canTakeAttendance: enabled,
  ),
  TeacherPermission.canCorrectAttendance => value.copyWith(
    canCorrectAttendance: enabled,
  ),
  TeacherPermission.canExportReports => value.copyWith(
    canExportReports: enabled,
  ),
  TeacherPermission.canViewParentContacts => value.copyWith(
    canViewParentContacts: enabled,
  ),
  TeacherPermission.canSendManualNotifications => value.copyWith(
    canSendManualNotifications: enabled,
  ),
};

String _permissionLabel(TeacherPermission value) => switch (value) {
  TeacherPermission.canCreateClasses => 'Create classes',
  TeacherPermission.canEditClasses => 'Edit classes',
  TeacherPermission.canAddStudents => 'Add students',
  TeacherPermission.canEditStudents => 'Edit students',
  TeacherPermission.canGenerateQrCodes => 'Generate QR codes',
  TeacherPermission.canTakeAttendance => 'Take attendance',
  TeacherPermission.canCorrectAttendance => 'Correct attendance',
  TeacherPermission.canExportReports => 'Export reports',
  TeacherPermission.canViewParentContacts => 'View parent contacts',
  TeacherPermission.canSendManualNotifications => 'Send manual notifications',
};

String _permissionDescription(TeacherPermission value) => switch (value) {
  TeacherPermission.canCreateClasses =>
    'Create a class in the teacher’s assigned institute.',
  TeacherPermission.canEditClasses =>
    'Edit classes only when the teacher is assigned to them.',
  TeacherPermission.canAddStudents =>
    'Prepared for the reviewed secure student-management backend.',
  TeacherPermission.canEditStudents =>
    'Prepared for assigned-student editing through the secure backend.',
  TeacherPermission.canGenerateQrCodes =>
    'Allow QR preparation where assigned-student access is available.',
  TeacherPermission.canTakeAttendance =>
    'Open attendance sessions and continuously scan assigned classes.',
  TeacherPermission.canCorrectAttendance =>
    'Submit attendance corrections with a required reason.',
  TeacherPermission.canExportReports =>
    'Export permitted class attendance reports.',
  TeacherPermission.canViewParentContacts =>
    'Show parent contacts only in an authorized student workflow.',
  TeacherPermission.canSendManualNotifications =>
    'Reserved for the later trusted notification backend.',
};

String _auditLabel(AuditAction value) => switch (value) {
  AuditAction.teacherCreated => 'Teacher created',
  AuditAction.teacherUpdated => 'Teacher updated',
  AuditAction.teacherDisabled => 'Teacher disabled',
  AuditAction.teacherReactivated => 'Teacher reactivated',
  AuditAction.teacherPermissionsChanged => 'Permissions changed',
  AuditAction.teacherPasswordResetRequested => 'Password reset requested',
  AuditAction.teacherFirstLoginCompleted => 'First login completed',
  _ => value.name,
};

String _dateTime(DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(TeacherStatus value) => switch (value) {
  TeacherStatus.active => 'Active',
  TeacherStatus.disabled => 'Disabled',
  TeacherStatus.pendingFirstLogin => 'Pending login',
};
