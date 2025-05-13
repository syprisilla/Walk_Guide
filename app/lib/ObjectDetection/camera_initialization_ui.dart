import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'camera_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({Key? key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Future<List<CameraDescription>>? _camerasFuture;

  @override
  void initState() {
    super.initState();

    _camerasFuture = _initializeCameras();
  }

  Future<List<CameraDescription>> _initializeCameras() async {
    try {
      return await availableCameras();
    } on CameraException catch (e) {
      print('사용할 카메라를 찾는 중 오류 발생 : ${e.code}, ${e.description}');
      return [];
    } catch (e) {
      print('사용할 카메라를 찾는 중 예기치 않은 오류 발생 : $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WalkGuide',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FutureBuilder<List<CameraDescription>>(
        future: _camerasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError ||
              snapshot.data == null ||
              snapshot.data!.isEmpty) {
            return const Scaffold(
              body: Center(
                  child: Text(
                '사용할 수 있는 카메라를 찾을 수 없습니다!\n카메라 권한 설정을 확인 후 다시 실행해주세요!',
                textAlign: TextAlign.center,
              )),
            );
          } else {
            return RealtimeObjectDetectionScreen(cameras: snapshot.data!);
          }
        },
      ),
    );
  }
}
