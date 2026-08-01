import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../application/managed_password_reset_controller.dart';
import '../data/firebase_managed_password_reset_service.dart';
import '../data/firestore_teacher_password_recovery_repository.dart';

class InstituteAdminArea extends StatefulWidget {
  const InstituteAdminArea({
    super.key,
    required this.authController,
    this.resetController,
  });

  final AuthenticationController authController;
  final ManagedPasswordResetController? resetController;

  @override
  State<InstituteAdminArea> createState() => _InstituteAdminAreaState();
}

class _InstituteAdminAreaState extends State<InstituteAdminArea> {
  late final ManagedPasswordResetController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.resetController == null;
    controller =
        widget.resetController ??
        ManagedPasswordResetController(
          actor: widget.authController.state.profile!,
          service: FirebaseManagedPasswordResetService(),
          teacherRepository: FirestoreTeacherPasswordRecoveryRepository(),
        );
    controller.loadTeachers();
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Institute Admin dashboard'),
      actions: [
        IconButton(
          onPressed: widget.authController.signOut,
          icon: const Icon(Icons.logout),
          tooltip: 'Log out',
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Teacher password recovery',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Send Firebase password-reset instructions without viewing or replacing an existing password.',
          ),
          if (controller.result != null) ...[
            const SizedBox(height: 16),
            _ResetStatus(result: controller.result!),
          ],
          const SizedBox(height: 16),
          if (controller.loadingDirectory)
            const Center(child: CircularProgressIndicator())
          else if (controller.directoryError != null)
            Text(
              controller.directoryError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (controller.teachers.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.person_search_outlined),
                title: Text('No teacher accounts available'),
                subtitle: Text(
                  'Teacher management remains outside this recovery task.',
                ),
              ),
            )
          else
            ...controller.teachers.map(
              (teacher) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(teacher.displayName),
                  subtitle: Text(
                    teacher.active
                        ? teacher.email
                        : '${teacher.email}\nDisabled',
                  ),
                  isThreeLine: !teacher.active,
                  trailing: FilledButton.tonal(
                    key: Key('reset-${teacher.uid}'),
                    onPressed:
                        controller.loadingTargetUid != null || !teacher.active
                        ? null
                        : () => controller.send(teacher),
                    child: controller.loadingTargetUid == teacher.uid
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send Password Reset Email'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.security_outlined),
              title: Text('Existing passwords remain private'),
              subtitle: Text(
                'Accounts are not recreated when a temporary password is lost. Newly provisioned accounts still change their password at first login.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ResetStatus extends StatelessWidget {
  const _ResetStatus({required this.result});
  final PasswordResetResult result;

  @override
  Widget build(BuildContext context) => Card(
    color: result.succeeded
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      key: const Key('managedResetStatus'),
      leading: Icon(
        result.status == PasswordResetStatus.loading
            ? Icons.hourglass_top
            : result.succeeded
            ? Icons.mark_email_read_outlined
            : Icons.error_outline,
      ),
      title: Text(result.message),
    ),
  );
}
