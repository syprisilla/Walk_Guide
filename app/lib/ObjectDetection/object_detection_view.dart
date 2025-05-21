import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'mlkit_object_detection.dart';
import 'object_painter.dart';
import 'camera_screen.dart' show IsolateDataHolder;

class ObjectDetectionView extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(List<DetectedObject> objects)? onObjectsDetected;
  final ResolutionPreset resolutionPreset;

  const ObjectDetectionView({
    Key? key,
    required this.cameras,
    this.onObjectsDetected,
    this.resolutionPreset = ResolutionPreset.high,
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

  String? _initializationErrorMsg;
  Orientation? _currentDeviceOrientation;

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _initializationErrorMsg = "사용 가능한 카메라가 없습니다.\n앱 권한을 확인하거나 재시작해주세요.";
        });
      }
      return;
    }
    _objectDetector = initializeObjectDetector();
    _spawnIsolates().then((success) {
      if (success == false) {
        if (mounted) {
          setState(() {
            _initializationErrorMsg = "백그라운드 작업 초기화에 실패했습니다.";
          });
        }
        return;
      }
      if (widget.cameras.isNotEmpty) {
        _initializeCamera(widget.cameras[_cameraIndex]);
      }
    }).catchError((e, stacktrace) {
      print(
          "****** ObjectDetectionView initState (spawnIsolates catchError): $e");
      if (mounted) {
        setState(() {
          _initializationErrorMsg = "초기화 중 예상치 못한 오류 발생:\n$e";
        });
      }
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

  Future<bool> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print(
          "****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn.");
      return false;
    }

    try {
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
      return true;
    } catch (e) {
      print("****** ObjectDetectionView: Failed to spawn isolates: $e");
      return false;
    }
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
    } else if (_objectDetectionIsolateSendPort != null && message is SendPort) {
      print(
          "ObjectDetectionView: WARNING - Detection Isolate SendPort received AGAIN. Current: $_objectDetectionIsolateSendPort, New: $message");
    } else if (message is List<DetectedObject>) {
      List<DetectedObject> objectsToShow = [];
      if (message.isNotEmpty) {
        DetectedObject largestObject = message.reduce((curr, next) {
          final double areaCurr =
              curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext =
              next.boundingBox.width * next.boundingBox.height;
          return areaCurr > areaNext ? curr : next;
        });
        objectsToShow.add(largestObject);
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
      print(
          '****** ObjectDetectionView: Detection Isolate Error: ${message[1]}');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! List<DetectedObject>)) {
      print(
          '****** ObjectDetectionView: Detection Isolate exited or sent empty/null message.');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (_objectDetectionIsolateSendPort != null && message == null)
        _objectDetectionIsolateSendPort = null;
      if (_detectedObjects.isNotEmpty && mounted)
        setState(() => _detectedObjects = []);
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else {
      print(
          '****** ObjectDetectionView: Unexpected message from Detection Isolate: $message');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    }
  }

  void _handleRotationResult(dynamic message) {
    if (!mounted) return;

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
    } else if (_imageRotationIsolateSendPort != null && message is SendPort) {
      print(
          "ObjectDetectionView: WARNING - Rotation Isolate SendPort received AGAIN. Current: $_imageRotationIsolateSendPort, New: $message");
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
      print(
          '****** ObjectDetectionView: Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! InputImageRotation)) {
      print(
          '****** ObjectDetectionView: Rotation Isolate exited or sent empty/null message.');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (_imageRotationIsolateSendPort != null && message == null)
        _imageRotationIsolateSendPort = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else {
      print(
          '****** ObjectDetectionView: Unexpected message from Rotation Isolate: $message');
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
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _initializationErrorMsg = null;
      });
    }

    _cameraController = CameraController(
      cameraDescription,
      widget.resolutionPreset,
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
      print('****** ObjectDetectionView: Camera init error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _initializationErrorMsg = "카메라 시작에 실패했습니다.\n권한을 확인하거나 앱을 재시작해주세요.";
        });
      }
    }
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      print('****** ObjectDetectionView: Start stream error: $e');
      if (mounted) {
        setState(() {
          _initializationErrorMsg = "카메라 스트림 시작에 실패했습니다.";
        });
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (e) {
      print('****** ObjectDetectionView: Stop stream error: $e');
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
    if (!mounted || _isBusy || _imageRotationIsolateSendPort == null) return;
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
      final orientation =
          _currentDeviceOrientation ?? MediaQuery.of(context).orientation;
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
    } catch (e) {
      print("****** ObjectDetectionView: Error processing image: $e");
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
    _currentDeviceOrientation = MediaQuery.of(context).orientation;

    if (_initializationErrorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _initializationErrorMsg!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(widget.cameras.isEmpty ? '카메라 없음' : '카메라 초기화 중...'),
          ],
        ),
      );
    }

    final double cameraAspectRatio = _cameraController!.value.aspectRatio;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size parentSize = constraints.biggest;

        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: parentSize.width,
                height: parentSize.width / cameraAspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),
            if (_detectedObjects.isNotEmpty &&
                _lastImageSize != null &&
                _imageRotation != null)
              CustomPaint(
                size: parentSize,
                painter: ObjectPainter(
                  objects: _detectedObjects,
                  imageSize: _lastImageSize!,
                  screenSize: parentSize,
                  rotation: _imageRotation!,
                  cameraLensDirection:
                      widget.cameras[_cameraIndex].lensDirection,
                  cameraPreviewAspectRatio: cameraAspectRatio,
                ),
              ),
          ],
        );
      },
    );
  }
}
