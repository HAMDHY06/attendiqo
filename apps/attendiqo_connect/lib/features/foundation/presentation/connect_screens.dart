import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../../../routing/connect_router.dart';
import '../../../theme/connect_theme.dart';

class ConnectSplashScreen extends StatelessWidget {
  const ConnectSplashScreen({super.key, required this.message});
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
                'assets/images/Connect.png',
                height: 180,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.family_restroom_rounded,
                  size: 100,
                  color: ConnectTheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Attendiqo Connect',
                textAlign: TextAlign.center,
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

class ConnectPlaceholderScreen extends StatelessWidget {
  const ConnectPlaceholderScreen({
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

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your dashboard'),
      actions: [
        IconButton(
          onPressed: () => Navigator.pushNamed(context, ConnectRoutes.settings),
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
        Text(
          'Hello, ${controller.state.profile?.displayName ?? 'Parent'}',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Your secure parent session is ready.'),
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.lock_rounded, size: 48, color: ConnectTheme.accent),
                SizedBox(height: 12),
                Text('Phase 2 authentication active'),
                SizedBox(height: 8),
                Text(
                  'Student linking and attendance information remain intentionally unavailable until later phases.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
