import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart';
import 'bounding_box_painter.dart'; // 바운딩 박스 유틸리티 임포트
import 'name_tag_painter.dart';   // 네임태그 유틸리티 임포트
import 'package:google_mlkit_commons/google_mlkit_commons.dart'; // InputImageRotation

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  ObjectPainter({