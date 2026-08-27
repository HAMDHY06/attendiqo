import 'package:flutter/material.dart';

import 'enums.dart';
import 'notification_service.dart';

/// Permission-only settings. Preferences and notification history are not
/// exposed until their trusted backend and UI are separately approved.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.service});

  final AppNotificationLifecycle service;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationPermissionState? _state;
  bool _loading = false;
  String? _error;

  Future<void> _request() async {
    setState(() => _loading = true);
    try {
      final value = await widget.service.requestPermission();
      if (mounted) {
        setState(() {
          _state = value;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Notifications are unavailable right now.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSystemSettings() async {
    final opened = await widget.service.openSystemSettings();
    if (!opened && mounted) {
      setState(
        () => _error =
            'System notification settings are unavailable on this device.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notification settings')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permission: ${_state?.name ?? 'Not checked'}'),
          const SizedBox(height: 12),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _loading ? null : _request,
            child: Text(_loading ? 'Checking…' : 'Request permission'),
          ),
          if (_state == NotificationPermissionState.denied ||
              _state == NotificationPermissionState.permanentlyDenied)
            OutlinedButton(
              onPressed: _openSystemSettings,
              child: const Text('Open system settings'),
            ),
          const SizedBox(height: 8),
          const Text('Security alerts are required and cannot be turned off.'),
        ],
      ),
    ),
  );
}
