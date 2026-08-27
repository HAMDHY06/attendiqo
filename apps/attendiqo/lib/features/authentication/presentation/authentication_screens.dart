import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _message;
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    final sent = await widget.controller.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _message = sent
          ? 'If an eligible account exists, password-reset instructions have been sent.'
          : widget.controller.state.message;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Enter your account email. Firebase will send a secure reset link.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: FieldValidators.email,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset email'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _message!,
                      key: const Key('resetMessage'),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    required this.controller,
    this.message,
  });
  final AuthenticationController controller;
  final String? message;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.controller.changePassword(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Create a new password'),
      automaticallyImplyLeading: false,
      actions: [
        TextButton(
          onPressed: widget.controller.signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.password_rounded, size: 72),
                const SizedBox(height: 16),
                Text(
                  'Your temporary password must be replaced before continuing.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('newPasswordField'),
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText:
                        '10+ characters with upper, lower, number and special character',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: PasswordValidator.validateForCreation,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) =>
                      value == _password.text ? null : 'Passwords do not match',
                ),
                if (widget.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Change password'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AccessBlockedScreen extends StatelessWidget {
  const AccessBlockedScreen({
    super.key,
    required this.message,
    required this.onSignOut,
  });
  final String message;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 72,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  key: const Key('accessBlockedMessage'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Support: dev.hamdhytech@gmail.com',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Worker-backed join/status surface. It contains no Firestore membership
/// writes and deliberately hides reviewer controls from Teachers and Parents.
class MembershipAccessScreen extends StatefulWidget {
  const MembershipAccessScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<MembershipAccessScreen> createState() => _MembershipAccessScreenState();
}

class _MembershipAccessScreenState extends State<MembershipAccessScreen> {
  final _code = TextEditingController();
  UserRole _role = UserRole.teacher;
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  MembershipWorkflowRepository? get _workflow =>
      widget.controller.repository is MembershipWorkflowRepository
      ? widget.controller.repository as MembershipWorkflowRepository
      : null;
  String get _statusMessage {
    final status = widget.controller.state.memberships
        .where((item) => item.status != InstituteMembershipStatus.active)
        .map((item) => item.status)
        .firstOrNull;
    return switch (status) {
      InstituteMembershipStatus.pending =>
        'Your institute request is pending approval.',
      InstituteMembershipStatus.rejected =>
        'Your institute request was not approved. You may submit a new request.',
      InstituteMembershipStatus.suspended =>
        'Your institute access is suspended. Contact the institute.',
      InstituteMembershipStatus.revoked =>
        'Your institute access was revoked. Request access again if appropriate.',
      _ =>
        'Request access with an institute join code. A code never grants access by itself.',
    };
  }

  Future<void> _request() async {
    final workflow = _workflow;
    if (workflow == null || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await workflow.requestMembership(
        joinCode: _code.text,
        requestedRole: _role,
      );
      if (mounted) {
        setState(
          () => _message =
              'Request submitted. Approval is required before access is granted.',
        );
      }
    } on MembershipWorkerFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Institute access')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 64),
              const SizedBox(height: 16),
              Text(_message ?? _statusMessage, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Institute join code',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                items: const [
                  DropdownMenuItem(
                    value: UserRole.teacher,
                    child: Text('Teacher'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.instituteAdmin,
                    child: Text('Institute Admin'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _role = value ?? UserRole.teacher),
                decoration: const InputDecoration(labelText: 'Requested role'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _request,
                child: Text(_busy ? 'Submitting…' : 'Request access'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.controller.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MembershipReviewScreen extends StatefulWidget {
  const MembershipReviewScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<MembershipReviewScreen> createState() => _MembershipReviewScreenState();
}

class _MembershipReviewScreenState extends State<MembershipReviewScreen> {
  List<InstituteJoinRequest>? _requests;
  String? _error;
  bool _loading = true;
  MembershipWorkflowRepository? get _workflow =>
      widget.controller.repository is MembershipWorkflowRepository
      ? widget.controller.repository as MembershipWorkflowRepository
      : null;
  bool get _mayReview {
    final role = widget.controller.state.profile?.role;
    return role == UserRole.superAdmin || role == UserRole.instituteAdmin;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workflow = _workflow;
    if (!_mayReview || workflow == null) {
      setState(() {
        _loading = false;
        _error = 'Membership approvals are unavailable for this account.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final active = widget.controller.state.activeMembership?.instituteId;
      final values = await workflow.loadReviewableRequests();
      if (mounted) {
        setState(
          () => _requests =
              widget.controller.state.profile?.role == UserRole.superAdmin
              ? values
                    .where(
                      (item) => item.requestedRole == UserRole.instituteAdmin,
                    )
                    .toList()
              : values
                    .where(
                      (item) =>
                          item.instituteId == active &&
                          (item.requestedRole == UserRole.teacher ||
                              item.requestedRole == UserRole.parent),
                    )
                    .toList(),
        );
      }
    } on MembershipWorkerFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(InstituteJoinRequest item, bool approve) async {
    final workflow = _workflow;
    if (workflow == null) return;
    setState(() => _loading = true);
    try {
      await workflow.reviewRequest(requestId: item.requestId, approve: approve);
      await widget.controller.refreshMemberships();
      await _load();
    } on MembershipWorkerFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_requests?.isEmpty ?? true) {
      body = const Center(child: Text('No membership requests need review.'));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _requests!.length,
          itemBuilder: (_, index) {
            final item = _requests![index];
            return ListTile(
              title: Text('${item.requestedRole.name} request'),
              subtitle: const Text('Pending approval'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _review(item, false),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: () => _review(item, true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Membership approvals')),
      body: body,
    );
  }
}
