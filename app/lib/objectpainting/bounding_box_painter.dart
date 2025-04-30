import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart'; 
import 'package:camera/camera.dart'; 

class BoundingBoxUtils {
  static Rect scaleAndTranslateRect({
    required Rect boundingBox,
    required Size imageSize, 
    required Size canvasSize,
    required InputImageRotation rotation, 
    required CameraLensDirection cameraLensDirection, 
  }) {
    final double imageWidth = imageSize.width;
    final double imageHeight = imageSize.height;
    final double canvasWidth = canvasSize.width;
    final double canvasHeight = canvasSize.height;

    final double scaleX, scaleY;
    if (_isRotationSideways(rotation)) {
      scaleX = canvasWidth / imageHeight;
      scaleY = canvasHeight / imageWidth;
    } else {
      scaleX = canvasWidth / imageWidth;
      scaleY = canvasHeight / imageHeight;
    }

    double L, T, R, B;
    switch (rotation) {
      case InputImageRotation.rotation90deg: L = boundingBox.top * scaleX; T = (imageWidth - boundingBox.right) * scaleY; R = boundingBox.bottom * scaleX; B = (imageWidth - boundingBox.left) * scaleY; break;
      case InputImageRotation.rotation180deg: L = (imageWidth - boundingBox.right) * scaleX; T = (imageHeight - boundingBox.bottom) * scaleY; R = (imageWidth - boundingBox.left) * scaleX; B = (imageHeight - boundingBox.top) * scaleY; break;
      case InputImageRotation.rotation270deg: L = (imageHeight - boundingBox.bottom) * scaleX; T = boundingBox.left * scaleY; R = (imageHeight - boundingBox.top) * scaleX; B = boundingBox.right * scaleY; break;
      case InputImageRotation.rotation0deg: default: L = boundingBox.left * scaleX; T = boundingBox.top * scaleY; R = boundingBox.right * scaleX; B = boundingBox.bottom * scaleY; break;
    }

     if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
      double tempL = L; L = canvasWidth - R; R = canvasWidth - tempL;
    }

    
    L = L.clamp(0.0, canvasWidth); T = T.clamp(0.0, canvasHeight); R = R.clamp(0.0, canvasWidth); B = B.clamp(0.0, canvasHeight);
    if (L > R) { double temp = L; L = R; R = temp; } if (T > B) { double temp = T; T = B; B = temp; }

    return Rect.fromLTRB(L, T, R, B);
  }

  static void paintBoundingBox(Canvas canvas, Rect rect) {
    final Paint paintRect = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    if (rect.width > 0 && rect.height > 0) {
      canvas.drawRect(rect, paintRect);
    }
  }

   static bool _isRotationSideways(InputImageRotation rotation) {
   return rotation == InputImageRotation.rotation90deg ||
       rotation == InputImageRotation.rotation270deg;
  }
}
