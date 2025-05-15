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

  Future<void> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      return;
    }

    _objectDetectionReceivePort = ReceivePort();
    _objectDetectionIsolate = await Isolate.spawn(
        detectObjectsIsolateEntry,
        IsolateDataHolder(
            _objectDetectionReceivePort.sendPort, rootIsolateToken),
        onError: _objectDetectionReceivePort.sendPort,
        onExit: _objectDetectionReceivePort.sendPort,
        debugName: "ObjectDetectionIsolate_View");
    _objectDetectionSubscription =
        _objectDetectionReceivePort.listen(_handleDetectionResult);

    _imageRotationReceivePort = ReceivePort();
    _imageRotationIsolate = await Isolate.spawn(
        getImageRotationIsolateEntry, _imageRotationReceivePort.sendPort,
        onError: _imageRotationReceivePort.sendPort,
        onExit: _imageRotationReceivePort.sendPort,
        debugName: "ImageRotationIsolate_View");
    _imageRotationSubscription =
        _imageRotationReceivePort.listen(_handleRotationResult);
  }

  void _killIsolates() {
    _objectDetectionIsolate?.kill(priority: Isolate.immediate);
    _imageRotationIsolate?.kill(priority: Isolate.immediate);
    _objectDetectionIsolate = null;
    _imageRotationIsolate = null;
    _objectDetectionIsolateSendPort = null;
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (!mounted) return;

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
    } else if (message is List<DetectedObject>) {
      List<DetectedObject> objectsToShow = [];
      if (message.isNotEmpty) {
        DetectedObject closestObject = message.reduce((curr, next) {
          final double areaCurr =
              curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext =
              next.boundingBox.width * next.boundingBox.height;
          return areaCurr > areaNext ? curr : next;
        });
        objectsToShow.add(closestObject);
      }
      widget.onObjectsDetected?.call(objectsToShow);
      _isWaitingForDetection = false;
      if (mounted) {
        setState(() {
          _detectedObjects = objectsToShow;
          _imageRotation = _lastCalculatedRotation;
        });
      }
      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].toString().contains('Error')) {
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! List<DetectedObject>)) {
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (_objectDetectionIsolateSendPort != null && message == null)
        _objectDetectionIsolateSendPort = null;
      if (_detectedObjects.isNotEmpty && mounted)
        setState(() => _detectedObjects = []);
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else {
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    }
  }

  void _handleRotationResult(dynamic message) {
    if (!mounted) return;

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;

      if (_pendingImageDataBytes != null &&
          _objectDetectionIsolateSendPort != null &&
          message != null) {
        _isWaitingForDetection = true;
        _lastImageSize = Size(_pendingImageDataWidth!.toDouble(),
            _pendingImageDataHeight!.toDouble());
        final Map<String, dynamic> payload = {
          'bytes': _pendingImageDataBytes!,
          'width': _pendingImageDataWidth!,
          'height': _pendingImageDataHeight!,
          'rotation': message,
          'formatRaw': _pendingImageDataFormatRaw!,
          'bytesPerRow': _pendingImageDataBytesPerRow!,
        };
        _objectDetectionIsolateSendPort!.send(payload);
        _pendingImageDataBytes = null;
      } else {
        if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].toString().contains('Error')) {
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! InputImageRotation)) {
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (_imageRotationIsolateSendPort != null && message == null)
        _imageRotationIsolateSendPort = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else {
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _stopCameraStream();
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (mounted) setState(() => _isCameraInitialized = false);

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _cameraController!.initialize();
      await _startCameraStream();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _cameraIndex = widget.cameras.indexOf(cameraDescription);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCameraInitialized = false);
    }
  }
}
