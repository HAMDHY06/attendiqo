import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'app/connect_app.dart';

@pragma('vm:entry-point')
Future<void> attendiqoConnectBackgroundMessageHandler(
  RemoteMessage message,
) async {
  // Intentionally minimal: no UI, routes, tokens or payload logging in background.
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      attendiqoConnectBackgroundMessageHandler,
    );
    firebaseReady = true;
  } on FirebaseException {
    // Foundation mode remains runnable until platform setup is complete.
  }
  runApp(AttendiqoConnectApp(firebaseReady: firebaseReady));
}
