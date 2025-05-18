// lib/ui/object_painter.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart';

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size screenSize;
  final InputImageRotation rotation;
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
    if (imageSize.isEmpty || size.isEmpty) {
      return;
    }

    final Paint paintRect = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.lightGreenAccent;

    final Paint backgroundPaint = Paint()..color = Colors.black.withOpacity(0.6);

    for (final DetectedObject detectedObject in objects) {
      final Rect boundingBox = detectedObject.boundingBox;

      final bool IsImageRotatedSideways = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;

      final double originalImageWidth = IsImageRotatedSideways ? imageSize.height : imageSize.width;
      final double originalImageHeight = IsImageRotatedSideways ? imageSize.width : imageSize.height;

      final double scaleX = size.width / originalImageWidth;
      final double scaleY = size.height / originalImageHeight;

      final double scale = (originalImageWidth / originalImageHeight > size.width / size.height)
          ? size.height / originalImageHeight
          : size.width / originalImageWidth;

      final double scaledImageWidth = originalImageWidth * scale;
      final double scaledImageHeight = originalImageHeight * scale;

      final double offsetX = (size.width - scaledImageWidth) / 2.0;
      final double offsetY = (size.height - scaledImageHeight) / 2.0;

      Rect displayRect;
      double l, t, r, b;

      switch (rotation) {
        case InputImageRotation.rotation0deg:
          l = boundingBox.left * scale + offsetX;
          t = boundingBox.top * scale + offsetY;
          r = boundingBox.right * scale + offsetX;
          b = boundingBox.bottom * scale + offsetY;
          if (cameraLensDirection == CameraLensDirection.front) {
            final double tempL = l;
            l = size.width - r;
            r = size.width - tempL;
          }
          break;
        case InputImageRotation.rotation90deg:
          l = boundingBox.top * scale + offsetX;
          t = (originalImageWidth - boundingBox.right) * scale + offsetY;
          r = boundingBox.bottom * scale + offsetX;
          b = (originalImageWidth - boundingBox.left) * scale + offsetY;
          if (cameraLensDirection == CameraLensDirection.front) {
            final double tempT = t;
            t = size.height - b;
            b = size.height - tempT;
          }
          break;
        case InputImageRotation.rotation180deg:
          l = (originalImageWidth - boundingBox.right) * scale + offsetX;
          t = (originalImageHeight - boundingBox.bottom) * scale + offsetY;
          r = (originalImageWidth - boundingBox.left) * scale + offsetX;
          b = (originalImageHeight - boundingBox.top) * scale + offsetY;
          if (cameraLensDirection == CameraLensDirection.front) {
            final double tempL = l;
            l = size.width - r;
            r = size.width - tempL;
          }
          break;
        case InputImageRotation.rotation270deg:
          l = (originalImageHeight - boundingBox.bottom) * scale + offsetX;
          t = boundingBox.left * scale + offsetY;
          r = (originalImageHeight - boundingBox.top) * scale + offsetX;
          b = boundingBox.right * scale + offsetY;
            if (cameraLensDirection == CameraLensDirection.front) {
            final double tempT = t;
            t = size.height - b;
            b = size.height - tempT;
            }
          break;
      }
      displayRect = Rect.fromLTRB(l, t, r, b);

      canvas.drawRect(displayRect, paintRect);

      if (detectedObject.labels.isNotEmpty) {
        final label = detectedObject.labels.first;
        final TextSpan span = TextSpan(
          text: '${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
          style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold),
        );
        final TextPainter tp = TextPainter(
          text: span,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
        );
        tp.layout();

        final Rect textBackgroundRect = Rect.fromLTWH(
            displayRect.left,
            displayRect.top - tp.height - 4,
            tp.width + 8,
            tp.height + 4);
        canvas.drawRect(textBackgroundRect, backgroundPaint);
        tp.paint(canvas, Offset(displayRect.left + 4, displayRect.top - tp.height -2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection;
  }
}