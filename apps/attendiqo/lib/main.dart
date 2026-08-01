import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app/attendiqo_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } on FirebaseException {
    // Foundation mode remains runnable until platform setup is complete.
  }
  runApp(AttendiqoApp(firebaseReady: firebaseReady));
}
