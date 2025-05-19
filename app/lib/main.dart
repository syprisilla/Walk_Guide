import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/splash_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:walk_guide/datetime_adapter.dart'; //  DateTimeAdapter import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(WalkSessionAdapter()); // 기존 어댑터 등록
  Hive.registerAdapter(DateTimeAdapter()); //  DateTime 어댑터 등록

  await Hive.openBox<WalkSession>('walk_sessions'); // 기존 세션 박스
  await Hive.openBox<DateTime>('recent_steps'); // 실시간 속도용 박스

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
