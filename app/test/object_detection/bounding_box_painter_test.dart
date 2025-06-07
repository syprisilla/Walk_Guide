import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:camera/camera.dart';
import 'package:walk_guide/object_detection/bounding_box_painter.dart'; //
import 'dart:io'
    show Platform; // Required for Platform.isAndroid check in the original file

void main() {
  group('BoundingBoxUtils Tests', () {
    test('scaleAndTranslateRect should correctly scale and translate a Rect',
        () {
      final boundingBox = const Rect.fromLTWH(10, 20, 30, 40);
      final imageSize = const Size(100, 200);
      final canvasSize = const Size(200, 400);
      final rotation = InputImageRotation.rotation0deg;
      final cameraLensDirection = CameraLensDirection.back;

      final result = BoundingBoxUtils.scaleAndTranslateRect(
        boundingBox: boundingBox,
        imageSize: imageSize,
        canvasSize: canvasSize,
        rotation: rotation,
        cameraLensDirection: cameraLensDirection,
      );

      // Basic expectation: scaled coordinates.
      // L = 10 * (200/100) = 20
      // T = 20 * (400/200) = 40
      // R = (10+30) * (200/100) = 80
      // B = (20+40) * (400/200) = 120
      expect(result.left, closeTo(20.0, 0.01));
      expect(result.top, closeTo(40.0, 0.01));
      expect(result.right, closeTo(80.0, 0.01));
      expect(result.bottom, closeTo(120.0, 0.01));
    });

    test('scaleAndTranslateRect with rotation90deg', () {
      final boundingBox = const Rect.fromLTWH(10, 20, 30, 40); // x, y, w, h
      final imageSize = const Size(100, 200); // width, height
      final canvasSize = const Size(
          400, 200); // width, height (swapped due to rotation expectation)
      final rotation = InputImageRotation.rotation90deg;
      final cameraLensDirection = CameraLensDirection.back;

      final result = BoundingBoxUtils.scaleAndTranslateRect(
        boundingBox: boundingBox,
        imageSize: imageSize,
        canvasSize: canvasSize,
        rotation: rotation,
        cameraLensDirection: cameraLensDirection,
      );
      // For rotation90deg:
      // scaleX = canvasWidth / imageHeight = 400 / 200 = 2
      // scaleY = canvasHeight / imageWidth = 200 / 100 = 2
      // L = boundingBox.top * scaleX = 20 * 2 = 40
      // T = (imageWidth - boundingBox.right) * scaleY = (100 - (10+30)) * 2 = (100-40)*2 = 60*2 = 120
      // R = boundingBox.bottom * scaleX = (20+40) * 2 = 60 * 2 = 120
      // B = (imageWidth - boundingBox.left) * scaleY = (100 - 10) * 2 = 90 * 2 = 180
      expect(result.left, closeTo(40.0, 0.01));
      expect(result.top, closeTo(120.0, 0.01));
      expect(result.right, closeTo(120.0, 0.01));
      expect(result.bottom, closeTo(180.0, 0.01));
    });

    testWidgets('paintBoundingBox runs without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: _TestBoundingBoxPainter(
              rect: const Rect.fromLTWH(10, 10, 50, 50),
            ),
            size: const Size(100, 100),
          ),
        ),
      );
      // Check no exceptions were thrown.
      expect(tester.takeException(), isNull);
    });
  });
}

class _TestBoundingBoxPainter extends CustomPainter {
  final Rect rect;
  _TestBoundingBoxPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    BoundingBoxUtils.paintBoundingBox(canvas, rect); //
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
