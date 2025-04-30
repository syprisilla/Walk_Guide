import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';

class RealtimeObjectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RealtimeObjectDetectionScreen({Key? key, required this.cameras})
    : super(key: key);

  @override
  _RealtimeObjectDetectionScreenState createState() =>
      _RealtimeObjectDetectionScreenState();
}
