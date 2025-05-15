import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'mlkit_object_detection.dart';
import 'object_painter.dart';
import 'dart:io';
import 'camera_screen.dart' show IsolateDataHolder;

class ObjectDetectionView extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(List<DetectedObject> objects)? onObjectsDetected;

  const ObjectDetectionView({
    Key? key,
    required this.cameras,
    this.onObjectsDetected,
  }) : super(key: key);

  @override
  _ObjectDetectionViewState createState() => _ObjectDetectionViewState();
}

class _ObjectDetectionViewState extends State<ObjectDetectionView> {
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isBusy = false;
  List<DetectedObject> _detectedObjects = [];
  InputImageRotation? _imageRotation;
  late ObjectDetector _objectDetector;
  Size? _lastImageSize;

  Isolate? _objectDetectionIsolate;
  Isolate? _imageRotationIsolate;
  late ReceivePort _objectDetectionReceivePort;
  late ReceivePort _imageRotationReceivePort;
  SendPort? _objectDetectionIsolateSendPort;
  SendPort? _imageRotationIsolateSendPort;
  StreamSubscription? _objectDetectionSubscription;
  StreamSubscription? _imageRotationSubscription;

  bool _isWaitingForRotation = false;
  bool _isWaitingForDetection = false;
  InputImageRotation? _lastCalculatedRotation;
  Uint8List? _pendingImageDataBytes;
  int? _pendingImageDataWidth;
  int? _pendingImageDataHeight;
  int? _pendingImageDataFormatRaw;
  int? _pendingImageDataBytesPerRow;

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isEmpty) {
      return;
    }
    _objectDetector = initializeObjectDetector();
    _spawnIsolates().then((_) {
      _initializeCamera(widget.cameras[_cameraIndex]);
    }).catchError((e, stacktrace) {
      print("****** ObjectDetectionView initState Error: $e");
    });
  }

  @override
  void dispose() {
    _stopCameraStream();
    _objectDetectionSubscription?.cancel();
    _imageRotationSubscription?.cancel();
    _killIsolates();
    _cameraController?.dispose();
    _objectDetector.close();
    super.dispose();
  }
}
