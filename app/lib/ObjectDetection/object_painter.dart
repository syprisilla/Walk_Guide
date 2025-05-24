import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart'; // CameraLensDirection을 위해 추가
import 'dart:io'; // Platform을 위해 추가

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects; // DetectedObjectInfo 대신 DetectedObject를 받도록 유지 (단순화를 위해)
                                    // 만약 DetectedObjectInfo를 사용하려면 이 클래스도 수정 필요
  final Size imageSize; // 원본 이미지 크기
  final Size screenSize; // Painter가 그려지는 캔버스(화면) 크기
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final double cameraPreviewAspectRatio; // 카메라 프리뷰 위젯의 종횡비
  final bool showNameTags; // NameTag 표시 여부 플래그

  ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
    required this.cameraPreviewAspectRatio,
    this.showNameTags = false, // 기본적으로 NameTag를 표시하지 않음
  });

  @override
  void paint(Canvas canvas, Size size) { // 여기서 size는 screenSize와 동일
    if (imageSize.isEmpty || size.isEmpty || cameraPreviewAspectRatio <= 0) {
      return;
    }

    final Paint paintRect = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.lightGreenAccent;

    // 화면(size) 내에서 카메라 프리뷰가 실제로 그려지는 영역 계산
    Rect cameraViewRect;
    final double screenAspectRatio = size.width / size.height;

    if (screenAspectRatio > cameraPreviewAspectRatio) {
      // 화면이 프리뷰보다 가로로 넓음 (프리뷰는 세로로 꽉 참, 좌우 레터박스)
      final double fittedHeight = size.height;
      final double fittedWidth = fittedHeight * cameraPreviewAspectRatio;
      final double offsetX = (size.width - fittedWidth) / 2;
      cameraViewRect = Rect.fromLTWH(offsetX, 0, fittedWidth, fittedHeight);
    } else {
      // 화면이 프리뷰보다 세로로 김 (프리뷰는 가로로 꽉 참, 상하 레터박스)
      final double fittedWidth = size.width;
      final double fittedHeight = fittedWidth / cameraPreviewAspectRatio;
      final double offsetY = (size.height - fittedHeight) / 2;
      cameraViewRect = Rect.fromLTWH(0, offsetY, fittedWidth, fittedHeight);
    }

    for (final DetectedObject detectedObject in objects) {
      final Rect boundingBox = detectedObject.boundingBox; // ML Kit에서 반환된 바운딩 박스 (원본 이미지 좌표계)

      // ML Kit이 처리한 이미지의 크기 (회전 고려)
      final bool isImageRotatedSideways =
          rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg;

      final double mlImageWidth =
          isImageRotatedSideways ? imageSize.height : imageSize.width;
      final double mlImageHeight =
          isImageRotatedSideways ? imageSize.width : imageSize.height;

      if (mlImageWidth == 0 || mlImageHeight == 0) continue;

      // 스케일 팩터: ML Kit 이미지 좌표 -> cameraViewRect 내 좌표
      final double scaleX = cameraViewRect.width / mlImageWidth;
      final double scaleY = cameraViewRect.height / mlImageHeight;

      Rect displayRect; // 최종적으로 화면에 그려질 Rect (cameraViewRect 기준 아님, 전체 canvas 기준)
      double l, t, r, b; // cameraViewRect 내에서의 상대적 좌표

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

      // Android 전면 카메라 미러링 처리
      if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
        if (rotation == InputImageRotation.rotation0deg || rotation == InputImageRotation.rotation180deg) {
          final double tempL = l;
          l = cameraViewRect.width - r; // cameraViewRect.width 기준으로 미러링
          r = cameraViewRect.width - tempL;
        }
      }

      // cameraViewRect의 offset을 더하여 최종 화면 좌표로 변환
      displayRect = Rect.fromLTRB(
          cameraViewRect.left + l,
          cameraViewRect.top + t,
          cameraViewRect.left + r,
          cameraViewRect.top + b);

      // 실제 그려질 영역이 cameraViewRect를 벗어나지 않도록 클리핑
      displayRect = Rect.fromLTRB(
          displayRect.left.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.top.clamp(cameraViewRect.top, cameraViewRect.bottom),
          displayRect.right.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.bottom.clamp(cameraViewRect.top, cameraViewRect.bottom));

      if (displayRect.width > 0 && displayRect.height > 0) {
        canvas.drawRect(displayRect, paintRect);

        // NameTag 표시 로직 (showNameTags 플래그에 따라 결정)
        if (showNameTags && detectedObject.labels.isNotEmpty) {
          final Paint backgroundPaint = Paint()..color = Colors.black.withOpacity(0.6);
          final label = detectedObject.labels.first;
          final TextSpan span = TextSpan(
            text: ' ${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0, // 폰트 크기 조절 가능
                fontWeight: FontWeight.bold),
          );
          final TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          );
          tp.layout();

          // 텍스트 배경 위치 계산 (displayRect를 기준으로)
          // 위쪽 또는 아래쪽에 표시, cameraViewRect 경계 고려
          double textBgTop = displayRect.top - tp.height - 4; // 기본적으로 박스 위에
          if (textBgTop < cameraViewRect.top) { // 너무 위로 가면 박스 아래에
            textBgTop = displayRect.bottom + 2;
          }
          // 박스 아래에도 공간이 없으면 박스 안 위쪽에 (이 경우는 복잡해지므로 일단 위/아래만 고려)
          if (textBgTop + tp.height + 4 > cameraViewRect.bottom && displayRect.top - tp.height - 4 >= cameraViewRect.top) {
             textBgTop = displayRect.top - tp.height - 4; // 다시 위로
          } else if (textBgTop + tp.height + 4 > cameraViewRect.bottom) { // 그래도 넘치면 최대한 아래로
             textBgTop = cameraViewRect.bottom - tp.height - 4;
          }


          double textBgLeft = displayRect.left;
          // 텍스트가 cameraViewRect의 오른쪽 경계를 넘지 않도록
          if (textBgLeft + tp.width + 8 > cameraViewRect.right) {
            textBgLeft = cameraViewRect.right - tp.width - 8;
          }
          // 텍스트가 cameraViewRect의 왼쪽 경계를 넘지 않도록
          if (textBgLeft < cameraViewRect.left) {
            textBgLeft = cameraViewRect.left;
          }

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