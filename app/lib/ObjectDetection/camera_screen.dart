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

class IsolateDataHolder {
  final SendPort mainSendPort;
  final RootIsolateToken? rootIsolateToken;

  IsolateDataHolder(this.mainSendPort, this.rootIsolateToken);
}

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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용 가능한 카메라가 없습니다.')),
          );
        }
      }
    }).catchError((e, stacktrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('초기화 중 오류 발생: $e')),
        );
      }
    });
  }

  @override
  void dispose() {
    _stopCameraStream();
    _objectDetectionSubscription?.cancel();
    _imageRotationSubscription?.cancel();
    _killIsolates();
    _cameraController?.dispose().catchError((e) {});
    _objectDetector.close().catchError((e) {});
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
        debugName: "ObjectDetectionIsolate");
    _objectDetectionSubscription =
        _objectDetectionReceivePort.listen(_handleDetectionResult);

    _imageRotationReceivePort = ReceivePort();
    _imageRotationIsolate = await Isolate.spawn(
        getImageRotationIsolateEntry, _imageRotationReceivePort.sendPort,
        onError: _imageRotationReceivePort.sendPort,
        onExit: _imageRotationReceivePort.sendPort,
        debugName: "ImageRotationIsolate");
    _imageRotationSubscription =
        _imageRotationReceivePort.listen(_handleRotationResult);
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
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! List<DetectedObject>)) {
      _isWaitingForDetection = false;
      if (_objectDetectionIsolateSendPort != null && message == null) {
        _objectDetectionIsolateSendPort = null;
      }
      if (_detectedObjects.isNotEmpty && mounted) {
        setState(() {
          _detectedObjects = [];
        });
      }
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else {
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
      _imageRotation = message;

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
      if (_imageRotationIsolateSendPort != null && message == null) {
        _imageRotationIsolateSendPort = null;
      }
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
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '카메라 초기화 오류 (${cameraDescription.name}): ${e.description}')),
        );
        setState(() => _isCameraInitialized = false);
      }
    } catch (e, stacktrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('알 수 없는 카메라 오류 발생 (${cameraDescription.name}).')),
        );
        setState(() => _isCameraInitialized = false);
      }
    }
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) {
      return;
    }
    try {
      await _cameraController!.startImageStream(_processCameraImage);
    } catch (e, stacktrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카메라 스트림 시작 오류.')),
        );
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_cameraController!.value.isStreamingImages) {
      return;
    }
    try {
      await _cameraController!.stopImageStream();
    } catch (e, stacktrace) {
    } finally {
      if (mounted) {
        _isBusy = false;
        _isWaitingForRotation = false;
        _isWaitingForDetection = false;
        _pendingImageDataBytes = null;
      }
    }
  }

  void _processCameraImage(CameraImage image) {
    if (!mounted || _isBusy || _imageRotationIsolateSendPort == null) {
      return;
    }
    _isBusy = true;
    _isWaitingForRotation = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
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
              ? (Platform.isIOS
                  ? DeviceOrientation.landscapeRight
                  : DeviceOrientation.landscapeLeft)
              : DeviceOrientation.portraitUp;

      final Map<String, dynamic> rotationPayload = {
        'sensorOrientation': camera.sensorOrientation,
        'deviceOrientationIndex': deviceRotation.index,
      };
      _imageRotationIsolateSendPort!.send(rotationPayload);
    } catch (e, stacktrace) {
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
      cameraPreviewWidget = CameraPreview(_cameraController!);
    } else {
      cameraPreviewWidget = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          Text(widget.cameras.isEmpty ? '카메라 없음' : '카메라 초기화 중...'),
        ],
      );
    }

    final double cameraAspectRatio = (_isCameraInitialized &&
            _cameraController != null &&
            _cameraController!.value.isInitialized)
        ? _cameraController!.value.aspectRatio
        : 1.0;

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
              onPressed: _isBusy ? null : _switchCamera,
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isCameraInitialized &&
                _cameraController != null &&
                _cameraController!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: cameraAspectRatio,
                  child: cameraPreviewWidget,
                ),
              )
            else
              Center(child: cameraPreviewWidget),
            if (_isCameraInitialized &&
                _detectedObjects.isNotEmpty &&
                _lastImageSize != null &&
                _imageRotation != null)
              LayoutBuilder(builder: (context, constraints) {
                return CustomPaint(
                  size: constraints.biggest,
                  painter: ObjectPainter(
                    objects: _detectedObjects,
                    imageSize: _lastImageSize!,
                    screenSize: constraints.biggest,
                    rotation: _imageRotation!,
                    cameraLensDirection:
                        widget.cameras[_cameraIndex].lensDirection,
                    cameraPreviewAspectRatio: cameraAspectRatio,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
