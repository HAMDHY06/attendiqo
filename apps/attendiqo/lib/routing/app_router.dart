import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/authentication_screens.dart';
import '../features/app_shell/presentation/main_app_shell.dart';
import '../features/academic_management/presentation/academic_management_screens.dart';
import '../features/foundation/presentation/foundation_screens.dart';

abstract final class AppRoutes {
  static const forgotPassword = '/forgot-password';
  static const settings = '/settings';
  static const academicManagement = '/academic-management';
  static const membershipApprovals = '/membership-approvals';
}

abstract final class AppRouter {
  static Route<void> generate(
    RouteSettings settings, {
    required AuthenticationController controller,
    AppNotificationLifecycle? notificationService,
  }) {
    final page = switch (settings.name) {
      AppRoutes.forgotPassword => ForgotPasswordScreen(controller: controller),
      AppRoutes.settings => NotificationSettingsScreen(
        service: notificationService ?? const UnavailableNotificationService(),
      ),
      AppRoutes.academicManagement => _academicScreen(controller),
      AppRoutes.membershipApprovals => MembershipReviewScreen(
        controller: controller,
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
    Widget Function(AuthenticationController controller)? superAdminBuilder,
    Widget Function(AuthenticationController controller)? instituteAdminBuilder,
    Widget Function(AuthenticationController controller)? teacherBuilder,
    ValueListenable<String?>? notificationDestination,
    String? activeInstituteId,
  }) => switch (destination) {
    AuthDestination.superAdminDashboard =>
      superAdminBuilder?.call(controller) ??
          MainAppShell(
            key: ValueKey('management-super-admin'),
            authController: controller,
            notificationDestination: notificationDestination,
          ),
    AuthDestination.instituteAdminDashboard =>
      instituteAdminBuilder?.call(controller) ??
          MainAppShell(
            key: ValueKey('management-$activeInstituteId'),
            authController: controller,
            notificationDestination: notificationDestination,
          ),
    AuthDestination.teacherDashboard =>
      teacherBuilder?.call(controller) ??
          MainAppShell(
            key: ValueKey('management-$activeInstituteId'),
            authController: controller,
            notificationDestination: notificationDestination,
          ),
    _ => AccessBlockedScreen(
      message: 'This role is not supported by Attendiqo.',
      onSignOut: controller.signOut,
    ),
  };

  static Widget _academicScreen(AuthenticationController controller) {
    final profile = controller.state.profile;
    if (controller.state.status != AuthenticationStatus.authenticated ||
        profile == null ||
        !profile.active ||
        (profile.role != UserRole.superAdmin &&
            controller.state.activeMembership == null) ||
        !const {
          UserRole.superAdmin,
          UserRole.instituteAdmin,
          UserRole.teacher,
        }.contains(profile.role)) {
      return AccessBlockedScreen(
        message: 'Your current session cannot open academic management.',
        onSignOut: controller.signOut,
      );
    }
    return AcademicManagementArea(authController: controller);
  }
}
