import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../time/live_time.dart';

class RoleNavigationDestination {
  const RoleNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Single role-aware top-level shell. Child pages retain their state in IndexedStack.
class AttendiqoAppShell extends StatefulWidget {
  const AttendiqoAppShell({
    super.key,
    required this.profile,
    required this.authController,
    required this.destinations,
    required this.onSignOut,
    this.instituteName,
    this.instituteActive = true,
    this.notificationDestination,
  });
  final UserProfile profile;
  final AuthenticationController authController;
  final List<RoleNavigationDestination> destinations;
  final Future<void> Function() onSignOut;
  final String? instituteName;
  final bool instituteActive;

  /// Route-only, authorization-checked notification destination.
  final ValueListenable<String?>? notificationDestination;
  @override
  State<AttendiqoAppShell> createState() => _AttendiqoAppShellState();
}

class _AttendiqoAppShellState extends State<AttendiqoAppShell> {
  var _index = 0;
  final Set<int> _visitedIndexes = {0};

  void _select(int value) => setState(() {
    _index = value;
    _visitedIndexes.add(value);
  });

  @override
  void initState() {
    super.initState();
    widget.notificationDestination?.addListener(_openNotificationDestination);
  }

  @override
  void didUpdateWidget(covariant AttendiqoAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationDestination != widget.notificationDestination) {
      oldWidget.notificationDestination?.removeListener(
        _openNotificationDestination,
      );
      widget.notificationDestination?.addListener(_openNotificationDestination);
    }
  }

  void _openNotificationDestination() {
    final route = widget.notificationDestination?.value;
    if (route == null) return;
    final labels = widget.destinations.map((item) => item.label).toList();
    final target = switch (route) {
      'home' => labels.indexOf(
        widget.profile.role == UserRole.superAdmin ? 'Overview' : 'Home',
      ),
      'myClasses' => labels.indexOf('My Classes'),
      'attendance' => labels.indexOf('Attendance'),
      'profile' => labels.indexOf('Profile'),
      'institutes' => labels.indexOf('Institutes'),
      'monitoring' => labels.indexOf('Monitoring'),
      'audit' => labels.indexOf('Audit'),
      // Notices are only a safe generic shell destination until a trusted
      // notification inbox is deployed.
      'notices' => 0,
      _ => -1,
    };
    if (target >= 0 && target < widget.destinations.length) _select(target);
  }

  @override
  void dispose() {
    widget.notificationDestination?.removeListener(
      _openNotificationDestination,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.destinations[_index];
    final content = IndexedStack(
      index: _index,
      children: List.generate(
        widget.destinations.length,
        (index) => _visitedIndexes.contains(index)
            ? widget.destinations[index].page
            : const SizedBox.shrink(),
      ),
    );
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _select(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 840 && widget.destinations.length > 1;
          final showNavigation = widget.destinations.length > 1;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 16,
              title: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/Admin_Logo.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.fact_check),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(current.label),
                ],
              ),
              actions: [
                if (_activeMemberships.length > 1)
                  PopupMenuButton<String>(
                    tooltip: 'Switch institute',
                    onSelected: (instituteId) => widget.authController
                        .selectActiveInstitute(instituteId),
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
                                        .authController
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
                if (widget.profile.role == UserRole.superAdmin ||
                    widget.profile.role == UserRole.instituteAdmin)
                  IconButton(
                    tooltip: 'Membership approvals',
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed('/membership-approvals'),
                    icon: const Icon(Icons.how_to_reg_rounded),
                  ),
                IconButton(
                  tooltip: 'Notifications (not configured)',
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notifications are not configured yet.'),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                IconButton(
                  tooltip: 'Log out',
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Account menu',
                  onSelected: (value) async {
                    if (value == 'signOut') await widget.onSignOut();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'signOut', child: Text('Sign out')),
                  ],
                  icon: CircleAvatar(
                    child: Text(_initial(widget.profile.displayName)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            body: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: widget.destinations
                        .map(
                          (entry) => NavigationRailDestination(
                            icon: Icon(entry.icon),
                            selectedIcon: Icon(entry.selectedIcon),
                            label: Text(entry.label),
                          ),
                        )
                        .toList(),
                  ),
                if (wide) const VerticalDivider(width: 1),
                Expanded(child: SafeArea(top: false, child: content)),
              ],
            ),
            bottomNavigationBar: !showNavigation || wide
                ? null
                : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: widget.destinations
                        .map(
                          (entry) => NavigationDestination(
                            icon: Icon(entry.icon),
                            selectedIcon: Icon(entry.selectedIcon),
                            label: entry.label,
                          ),
                        )
                        .toList(),
                  ),
          );
        },
      ),
    );
  }

  List<InstituteMembership> get _activeMemberships =>
      ActiveInstituteSelection.activeForUser(
        widget.authController.state.memberships,
        widget.profile.uid,
      );
}

class RoleDashboardHeader extends StatefulWidget {
  const RoleDashboardHeader({
    super.key,
    required this.profile,
    required this.roleLabel,
    required this.icon,
    this.instituteName,
    this.instituteActive = true,
    this.subtitle,
  });
  final UserProfile profile;
  final String roleLabel;
  final IconData icon;
  final String? instituteName;
  final bool instituteActive;
  final String? subtitle;
  @override
  State<RoleDashboardHeader> createState() => _RoleDashboardHeaderState();
}

class _RoleDashboardHeaderState extends State<RoleDashboardHeader> {
  late final LiveTimeController _clock;
  @override
  void initState() {
    super.initState();
    _clock = LiveTimeController();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (_, _) {
      final now = _clock.value;
      final date = MaterialLocalizations.of(context).formatMediumDate(now);
      return Card(
        color: Theme.of(context).colorScheme.primary,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: .16),
                child: Icon(widget.icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${liveGreeting(now)}, ${widget.profile.displayName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle ?? widget.roleLabel,
                      style: const TextStyle(color: Color(0xFFE0E7FF)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _HeaderPill(widget.roleLabel),
                        _HeaderPill('$date • ${compactLiveTime(now)}'),
                        if (widget.instituteName != null)
                          _HeaderPill(
                            widget.instituteActive
                                ? widget.instituteName!
                                : '${widget.instituteName} • Inactive',
                          ),
                      ],
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

class _HeaderPill extends StatelessWidget {
  const _HeaderPill(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

String _initial(String value) =>
    value.trim().isEmpty ? '?' : value.trim().substring(0, 1).toUpperCase();
