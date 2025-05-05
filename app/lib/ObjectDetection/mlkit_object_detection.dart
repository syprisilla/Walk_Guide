import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';

ObjectDetector initializeObjectDetector() {
  print("Initializing ML Kit detector...");
  final options = ObjectDetectorOptions(
    mode: DetectionMode.stream,
    classifyObjects: true,
    multipleObjects: true,
  );
  return ObjectDetector(options: options);
}
