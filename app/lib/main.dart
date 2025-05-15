import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/splash_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';

List<CameraDescription> camerasGlobal = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(WalkSessionAdapter()); // 어댑터 등록
  await Hive.openBox<WalkSession>('walk_sessions');

  await Firebase.initializeApp();

  try {
    camerasGlobal = await availableCameras();
  } on CameraException catch (e) {
    print('Error finding cameras: ${e.code}, ${e.description}');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Flutter App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SplashScreen(cameras: camerasGlobal),
    );
  }
}
