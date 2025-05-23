// lib/ObjectDetection/object_detection_view.dart
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
// IsolateDataHolder의 정의를 camera_screen.dart에서 가져오거나,
// 별도의 파일로 분리하여 양쪽에서 import 하도록 합니다.
// 여기서는 camera_screen.dart에 정의된 것을 사용한다고 가정합니다.
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
  late ObjectDetector _objectDetector; // Main isolate's detector
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

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _initializationErrorMsg = "사용 가능한 카메라가 없습니다.\n앱 권한을 확인하거나 재시작해주세요.";
        });
      }
      return;
    }
    _objectDetector = initializeObjectDetector();
    print("ObjectDetectionView: Main isolate ObjectDetector initialized.");

    _spawnIsolates().then((success) {
      if (!success) {
        if (mounted && !_isDisposed) {
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
      print("****** ObjectDetectionView initState (_spawnIsolates catchError): $e\n$stacktrace");
      if (mounted && !_isDisposed) {
        setState(() {
          _initializationErrorMsg = "초기화 중 예상치 못한 오류 발생:\n$e";
        });
      }
    });
  }

  @override
  void dispose() {
    print("****** ObjectDetectionView: Dispose called.");
    _isDisposed = true;

    // dispose()는 동기적으로 실행되어야 하므로, 비동기 정리 작업은
    // Future.microtask 등을 사용하여 현재 이벤트 루프 사이클 이후에 실행되도록 예약합니다.
    // 이는 dispose()의 반환을 막지 않으면서 정리 작업을 수행하기 위함입니다.
    Future.microtask(() async {
      await _stopCameraStream();

      // 구독 취소
      await _objectDetectionSubscription?.cancel();
      _objectDetectionSubscription = null;
      await _imageRotationSubscription?.cancel();
      _imageRotationSubscription = null;
      print("****** ObjectDetectionView: Subscriptions cancelled.");

      // 메인 Isolate의 ReceivePort 닫기
      try {
        _objectDetectionReceivePort.close();
        print("****** ObjectDetectionView: Object detection receive port closed.");
      } catch (e) {
        print("****** ObjectDetectionView: Error closing object detection receive port: $e");
      }
      try {
        _imageRotationReceivePort.close();
        print("****** ObjectDetectionView: Image rotation receive port closed.");
      } catch (e) {
        print("****** ObjectDetectionView: Error closing image rotation receive port: $e");
      }

      // Isolate 종료 (종료 신호 전송)
      _killIsolates();

      // 카메라 컨트롤러 해제
      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error disposing CameraController: $e\n$stacktrace');
      }
      _cameraController = null;

      // 메인 Isolate의 ObjectDetector 해제
      try {
        await _objectDetector.close();
        print("****** ObjectDetectionView: Main ObjectDetector closed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error closing main ObjectDetector: $e\n$stacktrace');
      }
    });

    super.dispose();
    print("****** ObjectDetectionView: Dispose completed for super.");
  }

  Future<bool> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn isolates.");
      return false;
    }

    try {
      _objectDetectionReceivePort = ReceivePort();
      _objectDetectionIsolate = await Isolate.spawn(
          detectObjectsIsolateEntry,
          // IsolateDataHolder 생성자 호출 시 두 개의 인자만 전달
          IsolateDataHolder(_objectDetectionReceivePort.sendPort, rootIsolateToken),
          onError: _objectDetectionReceivePort.sendPort,
          onExit: _objectDetectionReceivePort.sendPort,
          debugName: "ObjectDetectionIsolate_View");
      _objectDetectionSubscription = _objectDetectionReceivePort.listen(_handleDetectionResult);
      print("****** ObjectDetectionView: ObjectDetectionIsolate spawned.");

      _imageRotationReceivePort = ReceivePort();
      _imageRotationIsolate = await Isolate.spawn(
          getImageRotationIsolateEntry, _imageRotationReceivePort.sendPort,
          onError: _imageRotationReceivePort.sendPort,
          onExit: _imageRotationReceivePort.sendPort,
          debugName: "ImageRotationIsolate_View");
      _imageRotationSubscription = _imageRotationReceivePort.listen(_handleRotationResult);
      print("****** ObjectDetectionView: ImageRotationIsolate spawned.");
      return true;
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Failed to spawn isolates: $e\n$stacktrace");
      _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
      if(mounted && !_isDisposed) setState(() {});
      return false;
    }
  }

  void _killIsolates() {
    if (_objectDetectionIsolateSendPort != null) {
        _objectDetectionIsolateSendPort!.send('shutdown');
        print("****** ObjectDetectionView: Sent 'shutdown' to DetectionIsolate.");
    } else {
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      _objectDetectionIsolate = null;
      print("****** ObjectDetectionView: DetectionIsolate killed (no SendPort).");
    }
    // _objectDetectionIsolateSendPort는 Isolate가 종료 신호를 받고 스스로 닫히면 더 이상 유효하지 않으므로,
    // 여기서 null로 설정하는 것보다 Isolate 종료 후 정리하는 것이 나을 수 있습니다.
    // 하지만 즉시 kill을 대비해 null로 설정합니다.
    _objectDetectionIsolateSendPort = null;

    if (_imageRotationIsolateSendPort != null) {
        _imageRotationIsolateSendPort!.send('shutdown');
        print("****** ObjectDetectionView: Sent 'shutdown' to RotationIsolate.");
    } else {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      _imageRotationIsolate = null;
      print("****** ObjectDetectionView: RotationIsolate killed (no SendPort).");
    }
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_detection') {
        print("****** ObjectDetectionView: Detection isolate acknowledged shutdown.");
        _objectDetectionIsolate?.kill(priority: Isolate.immediate); // 최종 확인 후 kill
        _objectDetectionIsolate = null;
        return;
    }

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
    } else if (message is List<DetectedObject>) {
      List<DetectedObject> objectsToShow = [];
      if (message.isNotEmpty) {
        DetectedObject largestObject = message.reduce((curr, next) {
          final double areaCurr = curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext = next.boundingBox.width * next.boundingBox.height;
          return areaCurr > areaNext ? curr : next;
        });
        objectsToShow.add(largestObject);
      }
      widget.onObjectsDetected?.call(objectsToShow);
      _isWaitingForDetection = false;
      if (mounted && !_isDisposed) {
        setState(() {
          _detectedObjects = objectsToShow;
          // _imageRotation은 _handleRotationResult에서 업데이트되므로 여기서 직접 설정하지 않음
        });
      }
      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().contains('Error')) {
      print('****** ObjectDetectionView: Detection Isolate Error: ${message[1]}');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! List<DetectedObject>)) {
      print('****** ObjectDetectionView: Detection Isolate exited or sent empty/null message ($message).');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (_detectedObjects.isNotEmpty && mounted && !_isDisposed) setState(() => _detectedObjects = []);
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else {
      print('****** ObjectDetectionView: Unexpected message from Detection Isolate: ${message.runtimeType} - $message');
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    }
  }

  void _handleRotationResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_rotation') {
        print("****** ObjectDetectionView: Rotation isolate acknowledged shutdown.");
        _imageRotationIsolate?.kill(priority: Isolate.immediate); // 최종 확인 후 kill
        _imageRotationIsolate = null;
        return;
    }

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
      print("****** ObjectDetectionView: ImageRotationIsolate SendPort received.");
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;
      _imageRotation = message; // 페인팅에 사용될 _imageRotation 업데이트

      if (_pendingImageDataBytes != null && _objectDetectionIsolateSendPort != null && message != null) {
        _isWaitingForDetection = true;
        _lastImageSize = Size(_pendingImageDataWidth!.toDouble(), _pendingImageDataHeight!.toDouble());
        final Map<String, dynamic> payload = {
          'bytes': _pendingImageDataBytes!,
          'width': _pendingImageDataWidth!,
          'height': _pendingImageDataHeight!,
          'rotation': message,
          'formatRaw': _pendingImageDataFormatRaw!,
          'bytesPerRow': _pendingImageDataBytesPerRow!,
        };
        if (!_isDisposed && _objectDetectionIsolateSendPort != null) { // 전송 전 _isDisposed 및 SendPort 유효성 확인
             _objectDetectionIsolateSendPort!.send(payload);
        }
        _pendingImageDataBytes = null;
      } else {
        if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().contains('Error')) {
      print('****** ObjectDetectionView: Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! InputImageRotation)) {
      print('****** ObjectDetectionView: Rotation Isolate exited or sent empty/null message ($message).');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else {
      print('****** ObjectDetectionView: Unexpected message from Rotation Isolate: ${message.runtimeType} - $message');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_isDisposed) return;
    if (_cameraController != null) { // 기존 컨트롤러가 있다면 정리
      await _stopCameraStream(); // 스트림 먼저 중지
      await _cameraController!.dispose();
      _cameraController = null;
      print("****** ObjectDetectionView: Old CameraController disposed before new init.");
    }
    if (mounted && !_isDisposed) {
      setState(() {
        _isCameraInitialized = false;
        _initializationErrorMsg = null;
      });
    }

    _cameraController = CameraController(
      cameraDescription,
      widget.resolutionPreset,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await _cameraController!.initialize();
      print("****** ObjectDetectionView: New CameraController initialized for ${cameraDescription.name}.");
      await _startCameraStream();
      if (mounted && !_isDisposed) {
        setState(() {
          _isCameraInitialized = true;
          _cameraIndex = widget.cameras.indexOf(cameraDescription);
        });
      }
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Camera init error for ${cameraDescription.name}: $e\n$stacktrace');
      if (mounted && !_isDisposed) {
        setState(() {
          _isCameraInitialized = false;
          _initializationErrorMsg = "카메라 시작에 실패했습니다.\n권한을 확인하거나 앱을 재시작해주세요.\n오류: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
        });
      }
    }
  }

  Future<void> _startCameraStream() async {
    if (_isDisposed || _cameraController == null || !_cameraController!.value.isInitialized || _cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.startImageStream(_processCameraImage);
      print("****** ObjectDetectionView: Camera stream started for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Start stream error: $e\n$stacktrace');
      if (mounted && !_isDisposed) {
        setState(() {
          _initializationErrorMsg = "카메라 스트림 시작에 실패했습니다: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
        });
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || !_cameraController!.value.isStreamingImages) {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      print("****** ObjectDetectionView: Camera stream stopped in _stopCameraStream for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Stop stream error in _stopCameraStream: $e\n$stacktrace');
    } finally {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isDisposed || !mounted || _isBusy || _imageRotationIsolateSendPort == null) {
      if(_isBusy && !_isDisposed) {
         // print("Skipping frame, busy");
      }
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
      _pendingImageDataBytesPerRow = image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0;

      final camera = widget.cameras[_cameraIndex];
      final orientation = _currentDeviceOrientation ?? MediaQuery.of(context).orientation;
      final DeviceOrientation deviceRotation = (orientation == Orientation.landscape)
          ? (Platform.isIOS ? DeviceOrientation.landscapeRight : DeviceOrientation.landscapeLeft)
          : DeviceOrientation.portraitUp;
      final Map<String, dynamic> rotationPayload = {
        'sensorOrientation': camera.sensorOrientation,
        'deviceOrientationIndex': deviceRotation.index,
      };
      if (!_isDisposed && _imageRotationIsolateSendPort != null) { // 전송 전 _isDisposed 및 SendPort 유효성 확인
         _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
         _pendingImageDataBytes = null; // 데이터 전송 못하면 초기화
         _isWaitingForRotation = false;
         _isBusy = false;
      }
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Error processing image: $e\n$stacktrace");
      _pendingImageDataBytes = null;
      _isWaitingForRotation = false;
      _isBusy = false;
    }
  }

  void _switchCamera() {
    if (_isDisposed || widget.cameras.length < 2 || _isBusy) return;
    print("****** ObjectDetectionView: Switching camera...");
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    Future.microtask(() async {
        await _stopCameraStream(); // 현재 스트림 중지
        if (!_isDisposed && mounted) {
            await _initializeCamera(widget.cameras[newIndex]); // 새 카메라 초기화
        }
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

    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
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
        double previewWidth;
        double previewHeight;

        if (parentSize.width / parentSize.height > cameraAspectRatio) {
          previewHeight = parentSize.height;
          previewWidth = previewHeight * cameraAspectRatio;
        } else {
          previewWidth = parentSize.width;
          previewHeight = previewWidth / cameraAspectRatio;
        }

        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(_cameraController!),
              ),
            ),
            if (_detectedObjects.isNotEmpty && _lastImageSize != null && _imageRotation != null)
              CustomPaint(
                size: parentSize,
                painter: ObjectPainter(
                  objects: _detectedObjects,
                  imageSize: _lastImageSize!,
                  screenSize: parentSize,
                  rotation: _imageRotation!,
                  cameraLensDirection: widget.cameras[_cameraIndex].lensDirection,
                  cameraPreviewAspectRatio: cameraAspectRatio,
                ),
              ),
          ],
        );
      },
    );
  }
}