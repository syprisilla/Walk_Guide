// File: lib/ObjectDetection/object_painter.dart
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
  final bool showNameTags; // NameTag 표시 여부 플래그

  ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
    required this.cameraPreviewAspectRatio,
    this.showNameTags = false, 
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
          t = (mlImageHeight - boundingBox.right) * scaleY;
          r = boundingBox.bottom * scaleX;
          b = (mlImageHeight - boundingBox.left) * scaleY;
          break;
        case InputImageRotation.rotation180deg:
          l = (mlImageWidth - boundingBox.right) * scaleX;
          t = (mlImageHeight - boundingBox.bottom) * scaleY;
          r = (mlImageWidth - boundingBox.left) * scaleX;
          b = (mlImageHeight - boundingBox.top) * scaleY;
          break;
        case InputImageRotation.rotation270deg:
          l = (mlImageWidth - boundingBox.bottom) * scaleX;
          t = boundingBox.left * scaleY;
          r = (mlImageWidth - boundingBox.top) * scaleX;
          b = boundingBox.right * scaleY;
          break;
      }

      if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
        if (rotation == InputImageRotation.rotation0deg || rotation == InputImageRotation.rotation180deg) {
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
        // --- 바운더리 박스 좌우 크기 미세 조정 시작 ---
        const double horizontalPaddingFactor = 0.05; // 예: 박스 너비의 5%만큼 좌우로 줄임 (총 10%)
        final double horizontalPaddingAmount = displayRect.width * horizontalPaddingFactor;

        Rect adjustedDisplayRect = Rect.fromLTRB(
          displayRect.left + horizontalPaddingAmount,
          displayRect.top, 
          displayRect.right - horizontalPaddingAmount,
          displayRect.bottom,
        );

        // 조정된 박스의 너비가 0보다 작아지지 않도록 보정
        if (adjustedDisplayRect.width < 0) {
          // 너비가 음수면 중앙으로 모으거나, 원본을 사용
           adjustedDisplayRect = Rect.fromCenter(
                center: displayRect.center,
                width: 0, // 혹은 아주 작은 값
                height: displayRect.height,
            );
            if(adjustedDisplayRect.width < 0) adjustedDisplayRect = displayRect; // 최종 fallback
        }
        // --- 바운더리 박스 좌우 크기 미세 조정 끝 ---

        canvas.drawRect(adjustedDisplayRect, paintRect); // 조정된 박스를 그림

        if (showNameTags && detectedObject.labels.isNotEmpty) {
          final Paint backgroundPaint = Paint()..color = Colors.black.withOpacity(0.6);
          final label = detectedObject.labels.first;
          final TextSpan span = TextSpan(
            text: ' ${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
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

          // NameTag 위치를 adjustedDisplayRect 기준으로 계산
          double textBgTop = adjustedDisplayRect.top - tp.height - 4;
          if (textBgTop < cameraViewRect.top) { // 화면 상단 밖으로 나가지 않도록
            textBgTop = adjustedDisplayRect.bottom + 2;
          }
          // 화면 하단 밖으로 나가지 않도록 추가 조정
          if (textBgTop + tp.height + 4 > cameraViewRect.bottom) {
             if (adjustedDisplayRect.top - tp.height - 4 >= cameraViewRect.top) { // 위로 붙일 공간이 있다면
                textBgTop = adjustedDisplayRect.top - tp.height - 4;
             } else { // 그것도 안되면 최대한 아래쪽
                textBgTop = cameraViewRect.bottom - tp.height - 4;
             }
          }


          double textBgLeft = adjustedDisplayRect.left;
          if (textBgLeft + tp.width + 8 > cameraViewRect.right) { // 화면 오른쪽 밖으로 나가지 않도록
            textBgLeft = cameraViewRect.right - tp.width - 8;
          }
          if (textBgLeft < cameraViewRect.left) { // 화면 왼쪽 밖으로 나가지 않도록
            textBgLeft = cameraViewRect.left;
          }
          
          // 최종적으로 화면 경계 내에 있도록 한 번 더 clamp
          textBgTop = textBgTop.clamp(cameraViewRect.top, cameraViewRect.bottom - tp.height - 4);
          textBgLeft = textBgLeft.clamp(cameraViewRect.left, cameraViewRect.right - tp.width - 8);


          final Rect textBackgroundRect = Rect.fromLTWH(textBgLeft, textBgTop, tp.width + 8, tp.height + 4);

          canvas.drawRect(textBackgroundRect, backgroundPaint);
          tp.paint(canvas, Offset(textBackgroundRect.left + 4, textBackgroundRect.top + 2));
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
        oldDelegate.cameraPreviewAspectRatio != cameraPreviewAspectRatio ||
        oldDelegate.showNameTags != showNameTags;
  }
}