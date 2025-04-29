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
  })