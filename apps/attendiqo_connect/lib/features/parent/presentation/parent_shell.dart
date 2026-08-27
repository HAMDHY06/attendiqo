import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/parent_data_controller.dart';
import '../data/parent_projection_repository.dart';
import '../domain/parent_data.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({
    super.key,
    required this.controller,
    required this.repository,
    this.notificationDestination,
  });
  final AuthenticationController controller;
  final ParentProjectionRepository repository;
  final ValueListenable<String?>? notificationDestination;

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  var _index = 0;
  final Set<int> _visited = {0};
  late final ParentDataController _dataController;

  @override
  void initState() {
    super.initState();
    _dataController = ParentDataController(
      repository: widget.repository,
      parentProfile: widget.controller.state.profile!,
    )..start();
    widget.notificationDestination?.addListener(_openNotificationDestination);
  }

  void _select(int value) => setState(() {
    _index = value;
    _visited.add(value);
  });

  void _openNotificationDestination() {
    final route = widget.notificationDestination?.value;
    if (route == null) return;
    final target = switch (route) {
      'home' => 0,
      'children' || 'childProfile' => 1,
      'attendance' => 2,
      'notices' => 3,
      'profile' => 4,
      _ => -1,
    };
    if (target >= 0) _select(target);
  }

  Future<void> _signOut() async {
    _dataController.clearSession();
    await widget.controller.signOut();
  }

  @override
  void dispose() {
    widget.notificationDestination?.removeListener(
      _openNotificationDestination,
    );
    _dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.state.profile!;
    final pages = <Widget>[
      ParentHomePage(controller: _dataController, onNavigate: _select),
      ChildrenPage(controller: _dataController),
      AttendancePage(controller: _dataController),
      NoticesPage(controller: _dataController),
      ProfilePage(
        controller: _dataController,
        profile: profile,
        onSignOut: _signOut,
      ),
    ];
    const labels = ['Home', 'Children', 'Attendance', 'Notices', 'Profile'];
    const icons = [
      Icons.home_outlined,
      Icons.family_restroom_outlined,
      Icons.fact_check_outlined,
      Icons.notifications_none_rounded,
      Icons.person_outline,
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _select(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return Scaffold(
            appBar: AppBar(
              title: Text(labels[_index]),
              actions: [
                if (_activeMemberships.length > 1)
                  PopupMenuButton<String>(
                    tooltip: 'Switch institute',
                    onSelected: (instituteId) =>
                        widget.controller.selectActiveInstitute(instituteId),
                    itemBuilder: (_) => [
                      for (
                        var index = 0;
                        index < _activeMemberships.length;
                        index++
                      )
                        PopupMenuItem(
                          value: _activeMemberships[index].instituteId,
                          child: Text(
                            _activeMemberships[index].instituteId ==
                                    widget
                                        .controller
                                        .state
                                        .activeMembership
                                        ?.instituteId
                                ? 'Current institute'
                                : 'Switch to institute ${index + 1}',
                          ),
                        ),
                    ],
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _dataController.retryLinks,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
            body: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: _index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: _select,
                    destinations: List.generate(
                      labels.length,
                      (index) => NavigationRailDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(icons[index]),
                        label: Text(labels[index]),
                      ),
                    ),
                  ),
                if (wide) const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: List.generate(
                      pages.length,
                      (index) => _visited.contains(index)
                          ? pages[index]
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: List.generate(
                      labels.length,
                      (index) => NavigationDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(icons[index]),
                        label: labels[index],
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  List<InstituteMembership> get _activeMemberships =>
      ActiveInstituteSelection.activeForUser(
        widget.controller.state.memberships,
        widget.controller.state.profile!.uid,
      );
}

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({
    super.key,
    required this.controller,
    required this.onNavigate,
  });
  final ParentDataController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: () async => controller.retrySelectedChild(),
      child: ListView(
        key: const PageStorageKey('parent-home'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hello, ${controller.parentProfile.displayName}',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
          ),
          const SizedBox(height: 20),
          ChildSelector(controller: controller),
          const SizedBox(height: 16),
          _InstituteCard(controller: controller),
          const SizedBox(height: 16),
          _TodayCard(controller: controller),
          const SizedBox(height: 16),
          _NextClassCard(controller: controller),
          const SizedBox(height: 16),
          _RecentNotices(controller: controller),
          const SizedBox(height: 20),
          Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickAction(
                icon: Icons.fact_check_outlined,
                label: 'View attendance',
                onTap: () => onNavigate(2),
              ),
              _QuickAction(
                icon: Icons.badge_outlined,
                label: 'View child profile',
                onTap: () => onNavigate(1),
              ),
              _QuickAction(
                icon: Icons.calendar_month_outlined,
                label: 'View timetable',
                onTap: () => onNavigate(1),
              ),
              if ((controller.children.data
                          ?.where((item) => item.isSelectable)
                          .length ??
                      0) >
                  1)
                _QuickAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Switch child',
                  onTap: () => onNavigate(1),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ChildSelector extends StatelessWidget {
  const ChildSelector({super.key, required this.controller});
  final ParentDataController controller;

  @override
  Widget build(BuildContext context) {
    final selectable = (controller.children.data ?? const <LinkedChildRecord>[])
        .where((child) => child.isSelectable)
        .toList();
    if (controller.children.status == ParentDataStatus.loading) {
      return const LinearProgressIndicator(key: Key('children-loading'));
    }
    if (selectable.isEmpty) {
      return StatePanel(
        key: const Key('no-child-state'),
        icon: Icons.family_restroom_outlined,
        title: 'No child selected',
        message:
            controller.children.message ??
            'Securely linked child information is not available yet.',
        actionLabel: 'Retry',
        onAction: controller.retryLinks,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('child-selector'),
            isExpanded: true,
            value: controller.selectedChild?.link.studentId,
            hint: const Text('Select a child'),
            items: selectable
                .map(
                  (child) => DropdownMenuItem(
                    value: child.link.studentId,
                    child: Text(
                      child.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) controller.selectChild(value);
            },
          ),
        ),
      ),
    );
  }
}

class ChildrenPage extends StatelessWidget {
  const ChildrenPage({super.key, required this.controller});
  final ParentDataController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: () async => controller.retryLinks(),
      child: ListView(
        key: const PageStorageKey('children-page'),
        padding: const EdgeInsets.all(16),
        children: [
          ChildSelector(controller: controller),
          const SizedBox(height: 16),
          for (final child
              in controller.children.data ?? const <LinkedChildRecord>[])
            _ChildCard(
              child: child,
              selected:
                  controller.selectedChild?.link.studentId ==
                  child.link.studentId,
              onTap: child.isSelectable
                  ? () => controller.selectChild(child.link.studentId)
                  : null,
            ),
          if (controller.selectedChild != null) ...[
            const SizedBox(height: 12),
            _ChildDetails(controller: controller),
            const SizedBox(height: 16),
            Text(
              'Assigned classes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _ClassesSection(controller: controller),
          ],
        ],
      ),
    ),
  );
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key, required this.controller});
  final ParentDataController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ChildSelector(controller: controller),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'History'),
              Tab(text: 'Summary'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AttendanceToday(controller: controller),
                _AttendanceHistory(controller: controller),
                _AttendanceSummary(controller: controller),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class NoticesPage extends StatelessWidget {
  const NoticesPage({super.key, required this.controller});
  final ParentDataController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: () async => controller.retrySelectedChild(),
      child: ListView(
        key: const PageStorageKey('notices-page'),
        padding: const EdgeInsets.all(16),
        children: [
          ChildSelector(controller: controller),
          const SizedBox(height: 16),
          if (controller.notices.status == ParentDataStatus.ready)
            for (final notice in controller.notices.data!)
              _NoticeCard(notice: notice)
          else
            StatePanel.fromState(
              state: controller.notices,
              icon: Icons.notifications_none_rounded,
              emptyTitle: 'No notices',
              onRetry: controller.retrySelectedChild,
            ),
        ],
      ),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    required this.profile,
    required this.onSignOut,
  });
  final ParentDataController controller;
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListView(
      key: const PageStorageKey('profile-page'),
      padding: const EdgeInsets.all(16),
      children: [
        CircleAvatar(
          radius: 34,
          child: Text(
            profile.displayName.isEmpty
                ? 'P'
                : profile.displayName[0].toUpperCase(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                subtitle: Text(profile.email),
              ),
              ListTile(
                leading: const Icon(Icons.family_restroom_outlined),
                title: const Text('Linked children'),
                subtitle: Text(
                  '${controller.children.data?.where((item) => item.isSelectable).length ?? 0}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Account status'),
                subtitle: Text(profile.active ? 'Active' : 'Inactive'),
              ),
              const ListTile(
                leading: Icon(Icons.help_outline_rounded),
                title: Text('Help and Support'),
                subtitle: Text('dev.hamdhytech@gmail.com'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}

class _InstituteCard extends StatelessWidget {
  const _InstituteCard({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    final profile = controller.institute.data;
    if (profile == null) {
      return StatePanel.fromState(
        state: controller.institute,
        icon: Icons.account_balance_outlined,
        emptyTitle: 'Institute unavailable',
        onRetry: controller.retrySelectedChild,
      );
    }
    final hasContact = [
      profile.publicPhone,
      profile.publicEmail,
      profile.publicAddress,
    ].any((value) => value != null && value.isNotEmpty);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_outlined),
        title: Text(profile.displayName),
        subtitle: hasContact
            ? const Text('Public institute contact is available')
            : null,
        trailing: hasContact
            ? const Tooltip(
                message: 'Contact institute',
                child: Icon(Icons.contact_phone_outlined),
              )
            : null,
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.attendanceToday.status != ParentDataStatus.ready) {
      return StatePanel.fromState(
        state: controller.attendanceToday,
        icon: Icons.fact_check_outlined,
        emptyTitle: 'No attendance today',
        onRetry: controller.retrySelectedChild,
      );
    }
    final today = controller.todayAttendance;
    if (today.isEmpty) {
      return const StatePanel(
        icon: Icons.fact_check_outlined,
        title: 'No attendance today',
        message: 'No real attendance projection exists for today.',
      );
    }
    final record = today.first;
    return Card(
      child: ListTile(
        leading: Icon(_statusIcon(record.status)),
        title: Text(_statusLabel(record.status)),
        subtitle: Text(
          '${controller.className(record.classId)} • ${_presenceLabel(record.currentPresenceState)}',
        ),
      ),
    );
  }
}

class _NextClassCard extends StatelessWidget {
  const _NextClassCard({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    final available =
        (controller.classes.data ?? const <ProjectedClassRecord>[])
            .map((item) => item.profile)
            .whereType<ParentClassProfile>()
            .where((item) => item.active)
            .toList();
    if (available.isEmpty) {
      return StatePanel.fromState(
        state: controller.classes,
        icon: Icons.calendar_month_outlined,
        emptyTitle: 'No upcoming class',
        onRetry: controller.retrySelectedChild,
      );
    }
    return _ClassCard(profile: available.first);
  }
}

class _RecentNotices extends StatelessWidget {
  const _RecentNotices({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    final values = controller.notices.data;
    if (values == null || values.isEmpty) {
      return StatePanel.fromState(
        state: controller.notices,
        icon: Icons.notifications_none_rounded,
        emptyTitle: 'No recent notices',
        onRetry: controller.retrySelectedChild,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent notices', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final notice in values.take(2)) _NoticeCard(notice: notice),
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.selected,
    required this.onTap,
  });
  final LinkedChildRecord child;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
    child: ListTile(
      onTap: onTap,
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(child.displayName),
      subtitle: child.profile == null
          ? const Text('Safe profile projection unavailable')
          : Text(
              '${child.profile!.studentNumber} • ${child.link.relationship}',
            ),
      trailing: child.isSelectable
          ? Icon(selected ? Icons.check_circle : Icons.chevron_right)
          : const Icon(Icons.info_outline),
    ),
  );
}

class _ChildDetails extends StatelessWidget {
  const _ChildDetails({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    final child = controller.selectedChild!;
    final profile = child.profile!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.fullName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _DetailRow(label: 'Student number', value: profile.studentNumber),
            _DetailRow(label: 'Grade', value: profile.grade ?? 'Not provided'),
            _DetailRow(label: 'Relationship', value: child.link.relationship),
            _DetailRow(
              label: 'Status',
              value: profile.active ? 'Active' : 'Inactive',
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassesSection extends StatelessWidget {
  const _ClassesSection({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.classes.status != ParentDataStatus.ready) {
      return StatePanel.fromState(
        state: controller.classes,
        icon: Icons.class_outlined,
        emptyTitle: 'No assigned classes',
        onRetry: controller.retrySelectedChild,
      );
    }
    return Column(
      children: [
        for (final record in controller.classes.data!)
          if (record.profile != null)
            _ClassCard(profile: record.profile!)
          else
            const StatePanel(
              icon: Icons.info_outline,
              title: 'Class unavailable',
              message: 'A linked class projection has not been prepared yet.',
            ),
      ],
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.profile});
  final ParentClassProfile profile;
  @override
  Widget build(BuildContext context) {
    final schedule = profile.effectiveSchedule ?? profile.normalSchedule;
    final time =
        '${schedule['startTime'] ?? 'Time unavailable'}–${schedule['endTime'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.className,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(profile.active ? 'Active' : 'Inactive')),
              ],
            ),
            Text(
              '${profile.subject}${profile.grade == null ? '' : ' • ${profile.grade}'}',
            ),
            const SizedBox(height: 8),
            Text('$time${profile.room == null ? '' : ' • ${profile.room}'}'),
            if (profile.teacherDisplayName != null)
              Text('Teacher: ${profile.teacherDisplayName}'),
            if (profile.effectiveSchedule != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Temporary schedule applies',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceToday extends StatelessWidget {
  const _AttendanceToday({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.attendanceToday.status != ParentDataStatus.ready) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatePanel.fromState(
            state: controller.attendanceToday,
            icon: Icons.today_outlined,
            emptyTitle: 'No attendance today',
            onRetry: controller.retrySelectedChild,
          ),
        ],
      );
    }
    final values = controller.todayAttendance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: values.isEmpty
          ? const [
              StatePanel(
                icon: Icons.today_outlined,
                title: 'No attendance today',
                message: 'No real attendance projection exists for today.',
              ),
            ]
          : values
                .map(
                  (record) => _AttendanceCard(
                    record: record,
                    className: controller.className(record.classId),
                  ),
                )
                .toList(),
    );
  }
}

class _AttendanceHistory extends StatelessWidget {
  const _AttendanceHistory({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    final classProfiles =
        (controller.classes.data ?? const <ProjectedClassRecord>[])
            .where((item) => item.profile != null)
            .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const [
              null,
              'present',
              'absent',
              'late',
              'excused',
            ])
              FilterChip(
                label: Text(value == null ? 'All' : _statusLabel(value)),
                selected: controller.attendanceFilters.status == value,
                onSelected: (_) => controller.updateAttendanceFilters(
                  controller.attendanceFilters.copyWith(
                    status: value,
                    clearStatus: value == null,
                  ),
                ),
              ),
          ],
        ),
        if (classProfiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: controller.attendanceFilters.classId ?? '',
            decoration: const InputDecoration(labelText: 'Class filter'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All classes')),
              ...classProfiles.map(
                (item) => DropdownMenuItem(
                  value: item.classId,
                  child: Text(item.profile!.className),
                ),
              ),
            ],
            onChanged: (value) => controller.updateAttendanceFilters(
              controller.attendanceFilters.copyWith(
                classId: value,
                clearClass: value == null || value.isEmpty,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(_dateRangeLabel(context, controller.attendanceFilters)),
        const SizedBox(height: 12),
        if (controller.attendance.status == ParentDataStatus.ready)
          for (final record in controller.attendance.data!)
            _AttendanceCard(
              record: record,
              className: controller.className(record.classId),
            )
        else
          StatePanel.fromState(
            state: controller.attendance,
            icon: Icons.history_rounded,
            emptyTitle: 'No attendance history',
            onRetry: controller.retrySelectedChild,
          ),
      ],
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  const _AttendanceSummary({required this.controller});
  final ParentDataController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.attendance.status != ParentDataStatus.ready) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatePanel.fromState(
            state: controller.attendance,
            icon: Icons.analytics_outlined,
            emptyTitle: 'No attendance summary',
            onRetry: controller.retrySelectedChild,
          ),
        ],
      );
    }
    final summary = controller.computedSummary;
    if (summary == null) {
      return const Center(
        child: Text('No attendance records exist for this date range.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_dateRangeLabel(context, controller.attendanceFilters)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Metric(label: 'Present', value: '${summary.present}'),
            _Metric(label: 'Absent', value: '${summary.absent}'),
            _Metric(label: 'Late', value: '${summary.late}'),
            _Metric(label: 'Excused', value: '${summary.excused}'),
            _Metric(
              label: 'Attendance',
              value: '${summary.percentage.toStringAsFixed(1)}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.record, required this.className});
  final ParentAttendanceSummary record;
  final String className;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(_statusIcon(record.status)),
      title: Text('$className • ${_statusLabel(record.status)}'),
      subtitle: Text(
        '${MaterialLocalizations.of(context).formatMediumDate(record.attendanceDate)}\n'
        'Entry: ${_time(context, record.entryTime)} • Exit: ${_time(context, record.exitTime)}\n'
        '${_presenceLabel(record.currentPresenceState)}${record.late ? ' • Late' : ''}',
      ),
      isThreeLine: true,
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final ParentNotice notice;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                notice.priority == ParentNoticePriority.important
                    ? Icons.priority_high_rounded
                    : Icons.info_outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notice.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(notice.message),
          const SizedBox(height: 10),
          Text(
            '${_noticeContext(notice.targetType)} • ${MaterialLocalizations.of(context).formatMediumDate(notice.publishedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (notice.expiresAt != null)
            Text(
              'Available until ${MaterialLocalizations.of(context).formatMediumDate(notice.expiresAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
  );
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  factory StatePanel.fromState({
    required ParentDataState<Object?> state,
    required IconData icon,
    required String emptyTitle,
    VoidCallback? onRetry,
  }) {
    final title = switch (state.status) {
      ParentDataStatus.loading => 'Loading',
      ParentDataStatus.empty => emptyTitle,
      ParentDataStatus.unavailable => 'Information unavailable',
      ParentDataStatus.error => 'Unable to load information',
      ParentDataStatus.ready => emptyTitle,
    };
    final message =
        state.message ??
        switch (state.status) {
          ParentDataStatus.loading => 'Loading secure parent information…',
          ParentDataStatus.empty => 'No real records are available.',
          ParentDataStatus.unavailable =>
            'The trusted projection is not available yet.',
          ParentDataStatus.error => 'Check your connection and try again.',
          ParentDataStatus.ready => 'No records are available.',
        };
    return StatePanel(
      icon: icon,
      title: title,
      message: message,
      actionLabel: state.status == ParentDataStatus.loading ? null : 'Retry',
      onAction: state.status == ParentDataStatus.loading ? null : onRetry,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

String _time(BuildContext context, DateTime? value) => value == null
    ? 'Not recorded'
    : MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
String _statusLabel(String value) => switch (value) {
  'present' => 'Present',
  'absent' => 'Absent',
  'late' => 'Late',
  'excused' => 'Excused',
  _ => 'Unavailable',
};
IconData _statusIcon(String value) => switch (value) {
  'present' => Icons.check_circle_outline,
  'absent' => Icons.cancel_outlined,
  'late' => Icons.schedule_outlined,
  'excused' => Icons.info_outline,
  _ => Icons.help_outline,
};
String _presenceLabel(String value) => switch (value) {
  'inside' => 'Currently inside',
  'departed' => 'Departed',
  'outside' => 'Outside',
  _ => 'Presence unavailable',
};
String _noticeContext(ParentNoticeTargetType value) => switch (value) {
  ParentNoticeTargetType.instituteParents => 'Institute notice',
  ParentNoticeTargetType.student => 'Child notice',
  ParentNoticeTargetType.classTarget => 'Class notice',
};
String _dateRangeLabel(BuildContext context, AttendanceFilters filters) {
  final localizations = MaterialLocalizations.of(context);
  final from = filters.from == null
      ? 'Start'
      : localizations.formatMediumDate(filters.from!);
  final to = filters.to == null
      ? 'Today'
      : localizations.formatMediumDate(filters.to!);
  return '$from – $to';
}
