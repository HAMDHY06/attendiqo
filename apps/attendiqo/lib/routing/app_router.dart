import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/authentication_screens.dart';
import '../features/foundation/presentation/foundation_screens.dart';

abstract final class AppRoutes {
  static const forgotPassword = '/forgot-password';
  static const settings = '/settings';
}

abstract final class AppRouter {
  static Route<void> generate(
    RouteSettings settings, {
    required AuthenticationController controller,
  }) {
    final page = switch (settings.name) {
      AppRoutes.forgotPassword => ForgotPasswordScreen(controller: controller),
      AppRoutes.settings => const PlaceholderScreen(
        title: 'Settings',
        message:
            'Account settings beyond authentication remain planned for a later phase.',
      ),
      _ => const PlaceholderScreen(
        title: 'Not found',
        message: 'The requested screen does not exist.',
      ),
    };
    return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
  }

  static Widget screenForDestination(
    AuthDestination destination, {
    required AuthenticationController controller,
  }) => switch (destination) {
    AuthDestination.superAdminDashboard => DashboardShell(
      title: 'Super Admin dashboard',
      description: 'Secure Super Admin session ready.',
      controller: controller,
    ),
    AuthDestination.instituteAdminDashboard => DashboardShell(
      title: 'Institute Admin dashboard',
      description: 'Secure Institute Admin session ready.',
      controller: controller,
    ),
    AuthDestination.teacherDashboard => DashboardShell(
      title: 'Teacher dashboard',
      description: 'Secure Teacher session ready.',
      controller: controller,
    ),
    _ => AccessBlockedScreen(
      message: 'This role is not supported by Attendiqo.',
      onSignOut: controller.signOut,
    ),
  };
}
