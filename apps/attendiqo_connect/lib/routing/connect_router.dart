import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/connect_authentication_screens.dart';
import '../features/foundation/presentation/connect_screens.dart';
import '../features/parent/presentation/parent_shell.dart';
import '../features/parent/data/parent_projection_repository.dart';

abstract final class ConnectRoutes {
  static const forgotPassword = '/forgot-password';
  static const settings = '/settings';
}

abstract final class ConnectRouter {
  static Route<void> generate(
    RouteSettings settings, {
    required AuthenticationController controller,
    AppNotificationLifecycle? notificationService,
  }) {
    final page = switch (settings.name) {
      ConnectRoutes.forgotPassword => ConnectForgotPasswordScreen(
        controller: controller,
      ),
      ConnectRoutes.settings => NotificationSettingsScreen(
        service: notificationService ?? const UnavailableNotificationService(),
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
    required ParentProjectionRepository parentRepository,
    ValueListenable<String?>? notificationDestination,
    String? activeInstituteId,
  }) => switch (destination) {
    AuthDestination.parentDashboard => ParentShell(
      key: ValueKey('connect-$activeInstituteId'),
      controller: controller,
      repository: parentRepository,
      notificationDestination: notificationDestination,
    ),
    _ => ConnectAccessBlockedScreen(
      message: 'This role is not supported by Attendiqo Connect.',
      onSignOut: controller.signOut,
    ),
  };
}
