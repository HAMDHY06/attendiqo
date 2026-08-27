import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'app/attendiqo_app.dart';

@pragma('vm:entry-point')
Future<void> attendiqoBackgroundMessageHandler(RemoteMessage message) async {
  // Intentionally minimal: no UI, routes, tokens or payload logging in background.
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(attendiqoBackgroundMessageHandler);
    firebaseReady = true;
  } on FirebaseException {
    // Foundation mode remains runnable until platform setup is complete.
  }
  runApp(AttendiqoApp(firebaseReady: firebaseReady));
}
