import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'mlkit_object_detection.dart';
import 'object_painter.dart';
import 'dart:io';
import 'camera_screen.dart' show IsolateDataHolder;

class ObjectDetectionView extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(List<DetectedObject> objects)? onObjectsDetected;

  const ObjectDetectionView({
    Key? key,
    required this.cameras,
    this.onObjectsDetected,
  }) : super(key: key);

  @override
  _ObjectDetectionViewState createState() => _ObjectDetectionViewState();
}
