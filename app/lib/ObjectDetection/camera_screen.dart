import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import './mlkit_object_detection.dart';
import './object_painter.dart';
import 'dart:io';

class RealtimeObjectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RealtimeObjectDetectionScreen({Key? key, required this.cameras})
      : super(key: key);

  @override
  _RealtimeObjectDetectionScreenState createState() =>
      _RealtimeObjectDetectionScreenState();
}

class _RealtimeObjectDetectionScreenState
    extends State<RealtimeObjectDetectionScreen> {
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
    _objectDetector = initializeObjectDetector();
    _spawnIsolates().then((_) {
      if (widget.cameras.isNotEmpty) {
        _initializeCamera(widget.cameras[0]);
      }
    }).catchError((e, stacktrace) {
      print("****** initState: Error spawning isolates: $e");
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

  Future<void> _spawnIsolates() async {
    Completer<void> rotationPortCompleter = Completer();
    Completer<void> detectionPortCompleter = Completer();
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;

    if (rootIsolateToken == null) {
      throw Exception("Root token null");
    }

    _objectDetectionReceivePort = ReceivePort();
    _objectDetectionIsolate = await Isolate.spawn(
      detectObjectsIsolateEntry,
      [_objectDetectionReceivePort.sendPort, rootIsolateToken],
      onError: _objectDetectionReceivePort.sendPort,
      onExit: _objectDetectionReceivePort.sendPort,
    );
    _objectDetectionSubscription = _objectDetectionReceivePort.listen(
      _handleDetectionResult,
    );

    _imageRotationReceivePort = ReceivePort();
    _imageRotationIsolate = await Isolate.spawn(
      getImageRotationIsolateEntry,
      _imageRotationReceivePort.sendPort,
      onError: _imageRotationReceivePort.sendPort,
      onExit: _imageRotationReceivePort.sendPort,
    );
    _imageRotationSubscription = _imageRotationReceivePort.listen(
      _handleRotationResult,
    );

    try {
      await Future.wait([
        rotationPortCompleter.future.timeout(const Duration(seconds: 5)),
        detectionPortCompleter.future.timeout(const Duration(seconds: 5)),
      ]);
    } catch (e) {
      _killIsolates();
      throw e;
    }
  }

  void _killIsolates() {
    try {
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
    } catch (e) {}
    try {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
    } catch (e) {}

    _objectDetectionIsolate = null;
    _imageRotationIsolate = null;
    _objectDetectionIsolateSendPort = null;
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
    } else if (message is List<DetectedObject>) {
      _isWaitingForDetection = false;
      if (mounted) {
        setState(() {
          _detectedObjects = message;
          _imageRotation = _lastCalculatedRotation;
        });
      }
      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].contains('Error')) {
      print('****** Object Detection Isolate Error: ${message[1]}');
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation) _isBusy = false;
    } else {}
  }

  void _handleRotationResult(dynamic message) {
    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;

      if (_pendingImageDataBytes != null &&
          _objectDetectionIsolateSendPort != null &&
          message != null) {
        _isWaitingForDetection = true;
        _lastImageSize = Size(
          _pendingImageDataWidth!.toDouble(),
          _pendingImageDataHeight!.toDouble(),
        );
        _objectDetectionIsolateSendPort!.send([
          _pendingImageDataBytes!,
          _pendingImageDataWidth!,
          _pendingImageDataHeight!,
          message,
          _pendingImageDataFormatRaw!,
          _pendingImageDataBytesPerRow!,
        ]);
        _pendingImageDataBytes = null;
      } else {
        if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].contains('Error')) {
      print('****** Image Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection) _isBusy = false;
    } else {}
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_cameraController != null) {
      await _stopCameraStream();
      await _cameraController!.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraInitialized = false);
    }

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _cameraController!.initialize();
      await _startCameraStream();
      if (mounted)
        setState(() {
          _isCameraInitialized = true;
          _cameraIndex = widget.cameras.indexOf(cameraDescription);
        });
    } on CameraException catch (e) {
    } catch (e) {}
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {}
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (e) {}

    _isBusy = false;
    _isWaitingForRotation = false;
    _isWaitingForDetection = false;
    _pendingImageDataBytes = null;
  }

  void _processCameraImage(CameraImage image) {
    if (_isBusy ||
        _imageRotationIsolateSendPort == null ||
        _objectDetectionIsolateSendPort == null) return;
    _isBusy = true;
    _isWaitingForRotation = true;
    _isWaitingForDetection = false;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes)
        allBytes.putUint8List(plane.bytes);
      _pendingImageDataBytes = allBytes.done().buffer.asUint8List();
      _pendingImageDataWidth = image.width;
      _pendingImageDataHeight = image.height;
      _pendingImageDataFormatRaw = image.format.raw;
      _pendingImageDataBytesPerRow =
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0;

      final camera = widget.cameras[_cameraIndex];
      final orientation = MediaQuery.of(context).orientation;
      final DeviceOrientation deviceRotation =
          (orientation == Orientation.landscape)
              ? DeviceOrientation.landscapeLeft
              : DeviceOrientation.portraitUp;

      _imageRotationIsolateSendPort!.send([
        camera.sensorOrientation,
        deviceRotation,
      ]);
    } catch (e, stacktrace) {
      print("****** Error processing image: $e");
      _pendingImageDataBytes = null;
      _isWaitingForRotation = false;
      _isBusy = false;
    }
  }

  void _switchCamera() {
    if (widget.cameras.length < 2 || _isBusy) return;
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    _stopCameraStream().then((_) {
      _initializeCamera(widget.cameras[newIndex]);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget cameraPreviewWidget;
    if (_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      cameraPreviewWidget = AspectRatio(
        aspectRatio: _cameraController!.value.aspectRatio,
        child: CameraPreview(_cameraController!),
      );
    } else {
      cameraPreviewWidget = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 객체 탐지'),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: Icon(
                widget.cameras[_cameraIndex].lensDirection ==
                        CameraLensDirection.front
                    ? Icons.camera_front
                    : Icons.camera_rear,
              ),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: cameraPreviewWidget),
          if (_isCameraInitialized &&
              _detectedObjects.isNotEmpty &&
              _lastImageSize != null &&
              _imageRotation != null)
            LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: constraints.biggest,
                  painter: ObjectPainter(
                    objects: _detectedObjects,
                    imageSize: _lastImageSize!,
                    rotation: _imageRotation!,
                    cameraLensDirection:
                        widget.cameras[_cameraIndex].lensDirection,
                  ),
                );
              },
            ),
          if (_isBusy)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
