import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/attendiqo_theme.dart';
import '../../password_recovery/data/firebase_managed_password_reset_service.dart';
import '../../teacher_management/presentation/teacher_management_screens.dart';
import '../../academic_management/presentation/academic_management_screens.dart';
import '../application/super_admin_controller.dart';
import '../data/firestore_institute_repository.dart';

class SuperAdminArea extends StatefulWidget {
  const SuperAdminArea({
    super.key,
    required this.authController,
    this.controller,
  });
  final AuthenticationController authController;
  final SuperAdminController? controller;
  @override
  State<SuperAdminArea> createState() => _SuperAdminAreaState();
}

class _SuperAdminAreaState extends State<SuperAdminArea> {
  late final SuperAdminController controller;
  late final bool ownsController;
  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        SuperAdminController(
          repository: FirestoreInstituteRepository(),
          provisioningService: kDebugMode
              ? MockInstituteAdminProvisioningService()
              : const UnavailableInstituteAdminProvisioningService(),
          passwordResetService: FirebaseManagedPasswordResetService(),
          actor: widget.authController.state.profile!,
        );
    controller.load();
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SuperAdminDashboard(
    controller: controller,
    authController: widget.authController,
  );
}

class SuperAdminDashboard extends StatelessWidget {
  const SuperAdminDashboard({
    super.key,
    required this.controller,
    required this.authController,
  });
  final SuperAdminController controller;
  final AuthenticationController authController;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final stats = controller.statistics;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Super Admin dashboard'),
          actions: [
            IconButton(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: authController.signOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
            ),
          ],
        ),
        body: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: controller.load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Institute management',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          'Total institutes',
                          stats.totalInstitutes,
                          Icons.apartment,
                        ),
                        _Metric(
                          'Active',
                          stats.activeInstitutes,
                          Icons.check_circle_outline,
                        ),
                        _Metric(
                          'Suspended',
                          stats.suspendedInstitutes,
                          Icons.pause_circle_outline,
                        ),
                        _Metric(
                          'Institute Admins',
                          stats.totalInstituteAdmins,
                          Icons.admin_panel_settings_outlined,
                        ),
                        _Metric(
                          'Push enabled',
                          stats.pushEnabledInstitutes,
                          Icons.notifications_active_outlined,
                        ),
                        _Metric(
                          'SMS enabled',
                          stats.smsEnabledInstitutes,
                          Icons.sms_outlined,
                        ),
                      ],
                    ),
                    if (controller.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.apartment,
                              color: AttendiqoTheme.primary,
                            ),
                            title: const Text('Institutes'),
                            subtitle: const Text(
                              'Search, create, edit, activate or suspend',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    InstituteListScreen(controller: controller),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('teacherMonitoringTile'),
                            leading: const Icon(
                              Icons.groups_outlined,
                              color: AttendiqoTheme.secondary,
                            ),
                            title: const Text('Teacher monitoring'),
                            subtitle: const Text(
                              'View and manage teachers across institutes',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => TeacherManagementArea(
                                  authController: authController,
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('academicMonitoringTile'),
                            leading: const Icon(
                              Icons.school_outlined,
                              color: AttendiqoTheme.primary,
                            ),
                            title: const Text('Academic monitoring'),
                            subtitle: const Text(
                              'View classes and student records across institutes',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AcademicManagementArea(
                                  authController: authController,
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.history,
                              color: AttendiqoTheme.accent,
                            ),
                            title: const Text('Audit logs'),
                            subtitle: const Text(
                              'Review institute administration activity',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AuditLogScreen(controller: controller),
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
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AttendiqoTheme.primary),
            const SizedBox(height: 12),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class InstituteListScreen extends StatelessWidget {
  const InstituteListScreen({super.key, required this.controller});
  final SuperAdminController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Institutes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<Institute>(
            context,
            MaterialPageRoute(
              builder: (_) => InstituteFormScreen(controller: controller),
            ),
          );
          if (created != null && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => InstituteDetailsScreen(
                  controller: controller,
                  institute: created,
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Create institute'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('instituteSearch'),
              onChanged: controller.setSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search by name or code',
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: InstituteFilter.values
                  .map(
                    (value) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(value.name),
                        selected: controller.filter == value,
                        onSelected: (_) => controller.setFilter(value),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: controller.visibleInstitutes.isEmpty
                ? const Center(
                    child: Text('No institutes match your search or filter.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.visibleInstitutes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final institute = controller.visibleInstitutes[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              institute.instituteCode.substring(0, 1),
                            ),
                          ),
                          title: Text(institute.name),
                          subtitle: Text(
                            '${institute.instituteCode} - ${institute.status.name}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
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
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class InstituteFormScreen extends StatefulWidget {
  const InstituteFormScreen({
    super.key,
    required this.controller,
    this.existing,
  });
  final SuperAdminController controller;
  final Institute? existing;
  @override
  State<InstituteFormScreen> createState() => _InstituteFormScreenState();
}

class _InstituteFormScreenState extends State<InstituteFormScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController code = TextEditingController(
    text: widget.existing?.instituteCode ?? '',
  );
  late final TextEditingController name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final TextEditingController contact = TextEditingController(
    text: widget.existing?.contactNumber ?? '',
  );
  late final TextEditingController email = TextEditingController(
    text: widget.existing?.email ?? '',
  );
  bool saving = false;
  @override
  void dispose() {
    code.dispose();
    name.dispose();
    address.dispose();
    contact.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    Institute? result;
    if (widget.existing == null) {
      result = await widget.controller.createInstitute(
        code: code.text,
        name: name.text,
        address: address.text,
        contactNumber: contact.text,
        email: email.text,
      );
    } else {
      final value = widget.existing!.copyWith(
        name: name.text.trim(),
        address: address.text.trim(),
        contactNumber: contact.text.trim(),
        email: email.text.trim(),
      );
      if (await widget.controller.save(value)) result = value;
    }
    if (mounted) {
      setState(() => saving = false);
      if (result != null) Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'Create institute' : 'Edit institute',
      ),
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            key: const Key('instituteCode'),
            controller: code,
            enabled: widget.existing == null,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Institute code'),
            validator: InstituteCodeValidator.validate,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('instituteName'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Institute name'),
            validator: (value) =>
                FieldValidators.required(value, label: 'Institute name'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: address,
            decoration: const InputDecoration(labelText: 'Address'),
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: contact,
            decoration: const InputDecoration(labelText: 'Contact number'),
            validator: (value) => MobileNumberValidator.validateRequired(
              value,
              label: 'Contact number',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: email,
            decoration: const InputDecoration(
              labelText: 'Contact email (optional)',
            ),
            validator: FieldValidators.optionalEmail,
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('saveInstitute'),
            onPressed: saving ? null : submit,
            child: saving
                ? const CircularProgressIndicator()
                : Text(
                    widget.existing == null
                        ? 'Create institute'
                        : 'Save changes',
                  ),
          ),
        ],
      ),
    ),
  );
}

class InstituteDetailsScreen extends StatefulWidget {
  const InstituteDetailsScreen({
    super.key,
    required this.controller,
    required this.institute,
  });
  final SuperAdminController controller;
  final Institute institute;
  @override
  State<InstituteDetailsScreen> createState() => _InstituteDetailsScreenState();
}

class _InstituteDetailsScreenState extends State<InstituteDetailsScreen> {
  late Institute institute = widget.institute;
  Future<void> changeStatus(InstituteStatus status) async {
    if (status == InstituteStatus.suspended) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Suspend institute?'),
          content: const Text(
            'Users at this institute will lose management access until it is reactivated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirmSuspension'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Suspend'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (await widget.controller.setStatus(institute, status)) {
      setState(
        () => institute = institute.copyWith(
          status: status,
          active: status == InstituteStatus.active,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(institute.name),
      actions: [
        IconButton(
          onPressed: () async {
            final updated = await Navigator.push<Institute>(
              context,
              MaterialPageRoute(
                builder: (_) => InstituteFormScreen(
                  controller: widget.controller,
                  existing: institute,
                ),
              ),
            );
            if (updated != null) setState(() => institute = updated);
          },
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
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
                Text(
                  institute.instituteCode,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  institute.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(institute.status.name),
                const SizedBox(height: 12),
                Text(institute.address),
                Text(institute.contactNumber),
                Text(
                  institute.email.isEmpty
                      ? 'No contact email'
                      : institute.email,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          children: [
            if (institute.status != InstituteStatus.suspended)
              OutlinedButton.icon(
                onPressed: () => changeStatus(InstituteStatus.suspended),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Suspend'),
              )
            else
              FilledButton.icon(
                onPressed: () => changeStatus(InstituteStatus.active),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Reactivate'),
              ),
            OutlinedButton(
              onPressed: () => changeStatus(InstituteStatus.inactive),
              child: const Text('Set inactive'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Institute Admins'),
                leading: const Icon(Icons.admin_panel_settings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => InstituteAdminListScreen(
                      controller: widget.controller,
                      institute: institute,
                    ),
                  ),
                ),
              ),
              ListTile(
                title: const Text('Push notification availability'),
                subtitle: Text(
                  institute.pushNotificationsEnabled ? 'Enabled' : 'Disabled',
                ),
                leading: const Icon(Icons.notifications_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final updated = await Navigator.push<Institute>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PushSettingsScreen(
                        controller: widget.controller,
                        institute: institute,
                      ),
                    ),
                  );
                  if (updated != null) setState(() => institute = updated);
                },
              ),
              ListTile(
                title: const Text('SMS settings'),
                subtitle: Text(
                  institute.smsEnabled
                      ? '${institute.smsUsedThisMonth}/${institute.smsMonthlyLimit} used'
                      : 'Disabled',
                ),
                leading: const Icon(Icons.sms_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final updated = await Navigator.push<Institute>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmsSettingsScreen(
                        controller: widget.controller,
                        institute: institute,
                      ),
                    ),
                  );
                  if (updated != null) setState(() => institute = updated);
                },
              ),
              ListTile(
                title: const Text('Audit logs'),
                leading: const Icon(Icons.history),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AuditLogScreen(
                      controller: widget.controller,
                      instituteId: institute.instituteId,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({
    super.key,
    required this.controller,
    required this.institute,
  });
  final SuperAdminController controller;
  final Institute institute;
  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen> {
  late bool enabled = widget.institute.pushNotificationsEnabled;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Push notification settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'This controls future push availability only. No FCM message is sent in this phase.',
        ),
        SwitchListTile(
          title: const Text('Allow push notifications'),
          value: enabled,
          onChanged: (value) => setState(() => enabled = value),
        ),
        FilledButton(
          onPressed: () async {
            final updated = widget.institute.copyWith(
              pushNotificationsEnabled: enabled,
            );
            if (await widget.controller.save(updated) && context.mounted) {
              Navigator.pop(context, updated);
            }
          },
          child: const Text('Save push settings'),
        ),
      ],
    ),
  );
}

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({
    super.key,
    required this.controller,
    required this.institute,
  });
  final SuperAdminController controller;
  final Institute institute;
  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  late bool enabled = widget.institute.smsEnabled;
  late bool paid = widget.institute.allowPaidExtraSms;
  late final limit = TextEditingController(
    text: '${widget.institute.smsMonthlyLimit}',
  );
  @override
  void dispose() {
    limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SMS settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'SMS is optional and no provider is configured. Usage is read-only.',
        ),
        SwitchListTile(
          title: const Text('Allow SMS'),
          value: enabled,
          onChanged: (value) => setState(() => enabled = value),
        ),
        TextFormField(
          controller: limit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Monthly SMS limit'),
        ),
        SwitchListTile(
          title: const Text('Allow paid SMS after limit'),
          value: paid,
          onChanged: enabled ? (value) => setState(() => paid = value) : null,
        ),
        ListTile(
          title: const Text('Used this month'),
          trailing: Text('${widget.institute.smsUsedThisMonth}'),
          subtitle: const Text('Managed by trusted backend; not editable'),
        ),
        FilledButton(
          onPressed: () async {
            final parsed = int.tryParse(limit.text);
            if (parsed == null || parsed < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter a valid monthly limit.')),
              );
              return;
            }
            final updated = widget.institute.copyWith(
              smsEnabled: enabled,
              smsMonthlyLimit: parsed,
              allowPaidExtraSms: enabled && paid,
            );
            if (await widget.controller.save(updated) && context.mounted) {
              Navigator.pop(context, updated);
            }
          },
          child: const Text('Save SMS settings'),
        ),
      ],
    ),
  );
}

class InstituteAdminListScreen extends StatefulWidget {
  const InstituteAdminListScreen({
    super.key,
    required this.controller,
    required this.institute,
  });
  final SuperAdminController controller;
  final Institute institute;
  @override
  State<InstituteAdminListScreen> createState() =>
      _InstituteAdminListScreenState();
}

class _InstituteAdminListScreenState extends State<InstituteAdminListScreen> {
  late Future<List<UserProfile>> future = widget.controller.admins(
    widget.institute.instituteId,
  );
  void refresh() => setState(
    () => future = widget.controller.admins(widget.institute.instituteId),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Institute Admins')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CreateInstituteAdminScreen(
              controller: widget.controller,
              institute: widget.institute,
            ),
          ),
        );
        refresh();
      },
      icon: const Icon(Icons.person_add),
      label: const Text('Create admin'),
    ),
    body: FutureBuilder<List<UserProfile>>(
      future: future,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final admins = snapshot.data ?? [];
        if (admins.isEmpty) {
          return const Center(child: Text('No Institute Admin accounts yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: admins.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final admin = admins[i];
            return Card(
              child: ListTile(
                title: Text(admin.displayName),
                subtitle: Text(
                  '${admin.email}\n${admin.active ? 'Active' : 'Disabled'}',
                ),
                isThreeLine: true,
                trailing: widget.controller.resettingUid == admin.uid
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'reset') {
                            final operation = widget.controller
                                .resetAdminPassword(admin);
                            setState(() {});
                            final result = await operation;
                            if (context.mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            }
                          }
                          if (value == 'disable') {
                            if (await widget.controller.disableAdmin(admin)) {
                              refresh();
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(widget.controller.error!),
                                ),
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'reset',
                            child: Text('Send Password Reset Email'),
                          ),
                          if (admin.active)
                            const PopupMenuItem(
                              value: 'disable',
                              child: Text('Disable account'),
                            ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    ),
  );
}

class CreateInstituteAdminScreen extends StatefulWidget {
  const CreateInstituteAdminScreen({
    super.key,
    required this.controller,
    required this.institute,
  });
  final SuperAdminController controller;
  final Institute institute;
  @override
  State<CreateInstituteAdminScreen> createState() =>
      _CreateInstituteAdminScreenState();
}

class _CreateInstituteAdminScreenState
    extends State<CreateInstituteAdminScreen> {
  final key = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  bool loading = false;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!key.currentState!.validate()) return;
    setState(() => loading = true);
    final result = await widget.controller.createAdmin(
      InstituteAdminCreationRequest(
        instituteId: widget.institute.instituteId,
        email: email.text.trim(),
        displayName: name.text.trim(),
        actorUid: widget.controller.actorUid,
      ),
    );
    if (!mounted) return;
    setState(() => loading = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.error ?? 'Unable to create the account.',
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Admin created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy this temporary password now. It will not be shown again.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              result.oneTimeTemporaryPassword,
              key: const Key('temporaryPassword'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I saved it securely'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create Institute Admin')),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Institute: ${widget.institute.name}'),
          const SizedBox(height: 16),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Display name'),
            validator: (v) =>
                FieldValidators.required(v, label: 'Display name'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: FieldValidators.email,
          ),
          const SizedBox(height: 18),
          const Text(
            'A secure backend must create the real account. Development mode uses a local mock and sends nothing.',
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('createInstituteAdmin'),
            onPressed: loading ? null : submit,
            child: loading
                ? const CircularProgressIndicator()
                : const Text('Create admin'),
          ),
        ],
      ),
    ),
  );
}

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key, required this.controller, this.instituteId});
  final SuperAdminController controller;
  final String? instituteId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit logs')),
    body: FutureBuilder<List<AuditLogEntry>>(
      future: controller.repository.fetchAuditLogs(instituteId: instituteId),
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return const Center(child: Text('No audit entries found.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, i) {
            final log = logs[i];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(log.action.name),
              subtitle: Text(log.summary),
              trailing: Text(
                '${log.createdAt.year}-${log.createdAt.month.toString().padLeft(2, '0')}-${log.createdAt.day.toString().padLeft(2, '0')}',
              ),
            );
          },
        );
      },
    ),
  );
}
