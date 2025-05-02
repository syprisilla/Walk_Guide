import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(WalkSessionAdapter());

  await Hive.openBox<WalkSession>('walk_sessions');

  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Flutter App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }
}
