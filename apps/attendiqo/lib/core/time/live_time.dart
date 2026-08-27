import 'dart:async';

import 'package:flutter/foundation.dart';

/// Local display time only; it is never persisted or used for attendance data.
class LiveTimeController extends ChangeNotifier {
  LiveTimeController({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _value = _now();
      notifyListeners();
    });
  }

  final DateTime Function() _now;
  late final Timer _timer;
  DateTime? _value;
  DateTime get value => _value ?? _now();

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

String liveGreeting(DateTime value) => switch (value.hour) {
  < 12 => 'Good morning',
  < 17 => 'Good afternoon',
  _ => 'Good evening',
};

String compactLiveTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour < 12 ? 'AM' : 'PM'}';
}
