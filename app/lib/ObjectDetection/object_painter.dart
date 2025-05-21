import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart';
import 'dart:io';

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size screenSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final double cameraPreviewAspectRatio;

  ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
    required this.cameraPreviewAspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty || size.isEmpty || cameraPreviewAspectRatio <= 0) {
      return;
    }

    final Paint paintRect = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.lightGreenAccent;

    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.6);

    Rect cameraViewRect;
    final double screenAspectRatio = size.width / size.height;

    if (screenAspectRatio > cameraPreviewAspectRatio) {
      final double fittedHeight = size.height;
      final double fittedWidth = fittedHeight * cameraPreviewAspectRatio;
      final double offsetX = (size.width - fittedWidth) / 2;
      cameraViewRect = Rect.fromLTWH(offsetX, 0, fittedWidth, fittedHeight);
    } else {
      final double fittedWidth = size.width;
      final double fittedHeight = fittedWidth / cameraPreviewAspectRatio;
      final double offsetY = (size.height - fittedHeight) / 2;
      cameraViewRect = Rect.fromLTWH(0, offsetY, fittedWidth, fittedHeight);
    }

    for (final DetectedObject detectedObject in objects) {
      final Rect boundingBox = detectedObject.boundingBox;

      final bool isImageRotatedSideways =
          rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg;

      final double mlImageWidth =
          isImageRotatedSideways ? imageSize.height : imageSize.width;
      final double mlImageHeight =
          isImageRotatedSideways ? imageSize.width : imageSize.height;

      if (mlImageWidth == 0 || mlImageHeight == 0) continue;

      final double scaleX = cameraViewRect.width / mlImageWidth;
      final double scaleY = cameraViewRect.height / mlImageHeight;

      Rect displayRect;
      double l, t, r, b;

      switch (rotation) {
        case InputImageRotation.rotation0deg:
          l = boundingBox.left * scaleX;
          t = boundingBox.top * scaleY;
          r = boundingBox.right * scaleX;
          b = boundingBox.bottom * scaleY;
          break;
        case InputImageRotation.rotation90deg:
          l = boundingBox.top * scaleX;
          t = (mlImageWidth - boundingBox.right) * scaleY;
          r = boundingBox.bottom * scaleX;
          b = (mlImageWidth - boundingBox.left) * scaleY;
          break;
        case InputImageRotation.rotation180deg:
          l = (mlImageWidth - boundingBox.right) * scaleX;
          t = (mlImageHeight - boundingBox.bottom) * scaleY;
          r = (mlImageWidth - boundingBox.left) * scaleX;
          b = (mlImageHeight - boundingBox.top) * scaleY;
          break;
        case InputImageRotation.rotation270deg:
          l = (mlImageHeight - boundingBox.bottom) * scaleX;
          t = boundingBox.left * scaleY;
          r = (mlImageHeight - boundingBox.top) * scaleX;
          b = boundingBox.right * scaleY;
          break;
      }

      if (cameraLensDirection == CameraLensDirection.front &&
          Platform.isAndroid) {
        if (rotation == InputImageRotation.rotation0deg ||
            rotation == InputImageRotation.rotation180deg) {
          final double tempL = l;
          l = cameraViewRect.width - r;
          r = cameraViewRect.width - tempL;
        }
      }

      displayRect = Rect.fromLTRB(
          cameraViewRect.left + l,
          cameraViewRect.top + t,
          cameraViewRect.left + r,
          cameraViewRect.top + b);

      displayRect = Rect.fromLTRB(
          displayRect.left.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.top.clamp(cameraViewRect.top, cameraViewRect.bottom),
          displayRect.right.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.bottom.clamp(cameraViewRect.top, cameraViewRect.bottom));

      if (displayRect.width > 0 && displayRect.height > 0) {
        canvas.drawRect(displayRect, paintRect);

        if (detectedObject.labels.isNotEmpty) {
          final label = detectedObject.labels.first;
          final TextSpan span = TextSpan(
            text:
                ' ${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0,
                fontWeight: FontWeight.bold),
          );
          final TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          );
          tp.layout();

          double textBgTop = displayRect.top - tp.height - 4;
          if (textBgTop < cameraViewRect.top) {
            textBgTop = displayRect.top + 2;
          }
          if (textBgTop + tp.height + 4 > cameraViewRect.bottom) {
            textBgTop = displayRect.bottom - tp.height - 6;
          }

          double textBgLeft = displayRect.left;
          if (textBgLeft + tp.width + 8 > cameraViewRect.right) {
            textBgLeft = cameraViewRect.right - tp.width - 8;
          }
          if (textBgLeft < cameraViewRect.left) {
            textBgLeft = cameraViewRect.left;
          }

          final Rect textBackgroundRect =
              Rect.fromLTWH(textBgLeft, textBgTop, tp.width + 8, tp.height + 4);

          canvas.drawRect(textBackgroundRect, backgroundPaint);
          tp.paint(canvas,
              Offset(textBackgroundRect.left + 4, textBackgroundRect.top + 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.cameraPreviewAspectRatio != cameraPreviewAspectRatio;
  }
}
