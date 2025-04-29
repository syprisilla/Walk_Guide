import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';

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
}
