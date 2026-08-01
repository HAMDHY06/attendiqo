import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';
import '../../../theme/attendiqo_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/Admin_Logo.png',
                height: 180,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.fact_check_rounded,
                  size: 100,
                  color: AttendiqoTheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Attendiqo',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
  });
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );
}

class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.description,
    required this.controller,
    this.showAcademicManagement = false,
  });
  final String title;
  final String description;
  final AuthenticationController controller;
  final bool showAcademicManagement;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
        ),
        IconButton(
          onPressed: controller.signOut,
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Log out',
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
                  'Welcome, ${controller.state.profile?.displayName ?? 'User'}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(description),
                const SizedBox(height: 8),
                Text(controller.state.profile?.email ?? ''),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (showAcademicManagement)
          Card(
            child: ListTile(
              key: const Key('teacherAcademicManagement'),
              leading: const Icon(
                Icons.school_outlined,
                color: AttendiqoTheme.accent,
              ),
              title: const Text('Classes & students'),
              subtitle: const Text(
                'Open assigned classes and permitted academic actions.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.academicManagement),
            ),
          )
        else
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_rounded, color: AttendiqoTheme.accent),
              title: Text('Phase 2 authentication active'),
              subtitle: Text(
                'Additional management features remain intentionally unavailable.',
              ),
            ),
          ),
      ],
    ),
  );
}
