import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/connect_authentication_screens.dart';
import '../features/foundation/presentation/connect_screens.dart';

abstract final class ConnectRoutes {
  static const forgotPassword = '/forgot-password';
  static const settings = '/settings';
}

abstract final class ConnectRouter {
  static Route<void> generate(
    RouteSettings settings, {
    required AuthenticationController controller,
  }) {
    final page = switch (settings.name) {
      ConnectRoutes.forgotPassword => ConnectForgotPasswordScreen(
        controller: controller,
      ),
      ConnectRoutes.settings => const ConnectPlaceholderScreen(
        title: 'Settings',
        message:
            'Parent profile and notification preferences remain planned for a later phase.',
      ),
      _ => const ConnectPlaceholderScreen(
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
    AuthDestination.parentDashboard => ParentDashboardScreen(
      controller: controller,
    ),
    _ => ConnectAccessBlockedScreen(
      message: 'This role is not supported by Attendiqo Connect.',
      onSignOut: controller.signOut,
    ),
  };
}
