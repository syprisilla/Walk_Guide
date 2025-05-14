// lib/ui/object_painter.dart
import 'dart:ui' as ui; // ui.Image 사용 위함 (현재 코드에서는 직접 사용 안 함)
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart'; // CameraLensDirection

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize; // ML Kit이 처리한 원본 이미지의 크기 (회전 전 기준)
  final Size screenSize; // CustomPaint 위젯이 그려지는 실제 화면상의 크기
  final InputImageRotation rotation; // ML Kit 처리 시 사용된 이미지 회전
  final CameraLensDirection cameraLensDirection;

  ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;
    
    for (final DetectedObject detectedObject in objects) {
      // 1. 바운딩 박스 화면 좌표 계산
      final Rect canvasRect = BoundingBoxUtils.scaleAndTranslateRect(
        boundingBox: detectedObject.boundingBox,
        imageSize: imageSize,
        canvasSize: size,
        rotation: rotation,
        cameraLensDirection: cameraLensDirection,
      );

      BoundingBoxUtils.paintBoundingBox(canvas, canvasRect);

      // 3. 네임태그 그리기 (위임)
      if (detectedObject.labels.isNotEmpty) {
        NameTagUtils.paintNameTag(
           canvas: canvas,
          label: detectedObject.labels.first,
          boundingBoxRect: canvasRect, 
          canvasSize: size,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection;
  }
}
