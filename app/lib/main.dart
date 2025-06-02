import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/splash_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'package:walk_guide/nickname_input_page.dart';
List<CameraDescription> camerasGlobal = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(WalkSessionAdapter());
  Hive.registerAdapter(DateTimeAdapter()); // DateTime 어댑터 등록

  await Hive.openBox<WalkSession>('walk_sessions');
  await Hive.openBox<DateTime>('recent_steps'); //  recent_steps 박스 열기

  await Firebase.initializeApp();

  try {
    camerasGlobal = await availableCameras();
    print("📸 카메라 갯수: ${camerasGlobal.length}");
    for (var cam in camerasGlobal) {
      print(" - ${cam.name} (${cam.lensDirection})");
    }
  } on CameraException catch (e) {
    print('카메라 탐색 실패: $e');
    camerasGlobal = [];
  }

  runApp(
      MaterialApp(
        home: const NicknameInputPage(),
      )
  );
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

// DateTimeAdapter 추가
class DateTimeAdapter extends TypeAdapter<DateTime> {
  @override
  final int typeId = 99; // typeId는 고유해야 함

  @override
  DateTime read(BinaryReader reader) {
    return DateTime.fromMillisecondsSinceEpoch(reader.readInt());
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.millisecondsSinceEpoch);
  }
}
