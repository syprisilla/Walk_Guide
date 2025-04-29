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
