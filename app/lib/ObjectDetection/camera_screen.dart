// lib/ObjectDetection/camera_screen.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart'; // RootIsolateToken, DeviceOrientation
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'mlkit_object_detection.dart';
import 'object_painter.dart';
import 'dart:io' show Platform;

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

  // Isolate 핸들을 멤버 변수로 선언합니다. [필수 수정 사항]
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

  Size? _lastImageSize;
  Uint8List? _pendingImageDataBytes;
  int? _pendingImageDataWidth;
  int? _pendingImageDataHeight;
  int? _pendingImageDataFormatRaw;
  int? _pendingImageDataBytesPerRow;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    _objectDetector = initializeObjectDetector();
    print("RealtimeObjectDetectionScreen: ObjectDetector initialized.");

    // ReceivePort들을 initState 시작 시 바로 초기화합니다. [필수 수정 사항]
    _objectDetectionReceivePort = ReceivePort();
    _imageRotationReceivePort = ReceivePort();
    print("RealtimeObjectDetectionScreen: ReceivePorts initialized.");

    _spawnIsolates().then((success) {
      if (!success) {
        if (mounted && !_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('백그라운드 작업 스폰 실패.')),
          );
        }
        return;
      }
      if (widget.cameras.isNotEmpty) {
        _initializeCamera(widget.cameras[0]);
      } else {
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용 가능한 카메라가 없습니다.')),
          );
        }
      }
    }).catchError((e, stacktrace) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Isolate 스폰 중 오류: $e')),
        );
      }
      print('****** RealtimeObjectDetectionScreen: Isolate spawn error: $e\n$stacktrace');
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    print("RealtimeObjectDetectionScreen: Dispose called.");

    Future.microtask(() async {
      print("RealtimeObjectDetectionScreen: Dispose microtask started.");
      await _stopCameraStream();
      print("RealtimeObjectDetectionScreen: Camera stream stopped.");

      await _objectDetectionSubscription?.cancel();
      _objectDetectionSubscription = null;
      await _imageRotationSubscription?.cancel();
      _imageRotationSubscription = null;
      print("RealtimeObjectDetectionScreen: Stream subscriptions cancelled.");

      _killIsolates();
      print("RealtimeObjectDetectionScreen: Isolates kill requested.");

      _objectDetectionReceivePort.close();
      print("RealtimeObjectDetectionScreen: Object detection port closed.");
      _imageRotationReceivePort.close();
      print("RealtimeObjectDetectionScreen: Image rotation port closed.");

      await _cameraController?.dispose();
      _cameraController = null;
      print("RealtimeObjectDetectionScreen: CameraController disposed.");

      await _objectDetector.close();
      print("RealtimeObjectDetectionScreen: ObjectDetector closed.");
      print("RealtimeObjectDetectionScreen: Dispose microtask finished.");
    });

    super.dispose();
    print("RealtimeObjectDetectionScreen: super.dispose() completed.");
  }

  Future<bool> _spawnIsolates() async {
    print("RealtimeObjectDetectionScreen: Spawning isolates...");
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("RealtimeObjectDetectionScreen: RootIsolateToken is null.");
      return false;
    }

    try {
      // _objectDetectionIsolate와 _imageRotationIsolate에 할당합니다. [필수 수정 사항]
      _objectDetectionIsolate = await Isolate.spawn(
          detectObjectsIsolateEntry,
          IsolateDataHolder(_objectDetectionReceivePort.sendPort, rootIsolateToken),
          onError: _objectDetectionReceivePort.sendPort,
          onExit: _objectDetectionReceivePort.sendPort,
          debugName: "ObjectDetectionIsolate_Realtime");
      _objectDetectionSubscription = _objectDetectionReceivePort.listen(_handleDetectionResult);
      print("RealtimeObjectDetectionScreen: ObjectDetectionIsolate spawned.");

      _imageRotationIsolate = await Isolate.spawn(
          getImageRotationIsolateEntry,
          _imageRotationReceivePort.sendPort,
          onError: _imageRotationReceivePort.sendPort,
          onExit: _imageRotationReceivePort.sendPort,
          debugName: "ImageRotationIsolate_Realtime");
      _imageRotationSubscription = _imageRotationReceivePort.listen(_handleRotationResult);
      print("RealtimeObjectDetectionScreen: ImageRotationIsolate spawned.");
      return true;
    } catch (e, stacktrace) {
      print("****** RealtimeObjectDetectionScreen: Isolate spawn failed: $e\n$stacktrace");
      return false;
    }
  }

  void _killIsolates() {
    print("RealtimeObjectDetectionScreen: Attempting to kill isolates...");
    // _objectDetectionIsolate와 _imageRotationIsolate를 사용하여 kill을 호출합니다. [필수 수정 사항]
    if (_objectDetectionIsolateSendPort != null && _objectDetectionIsolate != null) {
      try {
        _objectDetectionIsolateSendPort!.send('shutdown');
        print("RealtimeObjectDetectionScreen: Sent 'shutdown' to DetectionIsolate.");
      } catch (e) {
        print("RealtimeObjectDetectionScreen: Error sending shutdown to DetectionIsolate: $e");
        _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      }
    } else {
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      print("RealtimeObjectDetectionScreen: DetectionIsolate killed directly.");
    }
    _objectDetectionIsolate = null;
    _objectDetectionIsolateSendPort = null;

    if (_imageRotationIsolateSendPort != null && _imageRotationIsolate != null) {
      try {
        _imageRotationIsolateSendPort!.send('shutdown');
        print("RealtimeObjectDetectionScreen: Sent 'shutdown' to RotationIsolate.");
      } catch (e) {
        print("RealtimeObjectDetectionScreen: Error sending shutdown to RotationIsolate: $e");
        _imageRotationIsolate?.kill(priority: Isolate.immediate);
      }
    } else {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      print("RealtimeObjectDetectionScreen: RotationIsolate killed directly.");
    }
    _imageRotationIsolate = null;
    _imageRotationIsolateSendPort = null;
    print("RealtimeObjectDetectionScreen: Isolates presumed terminated.");
  }

  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_detection') {
      print("RealtimeObjectDetectionScreen: Detection isolate ack shutdown.");
      return;
    }

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("RealtimeObjectDetectionScreen: DetectionIsolate SendPort received.");
      return;
    }

    List<DetectedObject> newDetectedObjects = [];
    if (message is List<DetectedObject>) {
      if (message.isNotEmpty) {
        DetectedObject largestObject = message.reduce((curr, next) {
          final double areaCurr = curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext = next.boundingBox.width * next.boundingBox.height;
          return areaCurr > areaNext ? curr : next;
        });
        newDetectedObjects.add(largestObject);
      }
    } else if (message is List && message.length == 2 && message[0].toString().startsWith('Error from DetectionIsolate')) {
      print('****** Detection Isolate Error: ${message[1]}');
    } else {
      print('RealtimeObjectDetectionScreen: Unexpected msg from DetectionIsolate: ${message.runtimeType}');
    }

    _isWaitingForDetection = false;
    if (mounted && !_isDisposed) {
      setState(() { _detectedObjects = newDetectedObjects; });
    }

    if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
       if (mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
    }
  }

  void _handleRotationResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_rotation') {
      print("RealtimeObjectDetectionScreen: Rotation isolate ack shutdown.");
      return;
    }

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
      print("RealtimeObjectDetectionScreen: RotationIsolate SendPort received.");
      return;
    }

    if (message is InputImageRotation?) {
      _imageRotation = message;
      _isWaitingForRotation = false;

      if (_pendingImageDataBytes != null &&
          _objectDetectionIsolateSendPort != null &&
          _imageRotation != null &&
          !_isDisposed) {
        _isWaitingForDetection = true;
        final Map<String, dynamic> payload = {
          'bytes': _pendingImageDataBytes!, 'width': _pendingImageDataWidth!,
          'height': _pendingImageDataHeight!, 'rotation': _imageRotation!,
          'formatRaw': _pendingImageDataFormatRaw!, 'bytesPerRow': _pendingImageDataBytesPerRow!,
        };
        if(_objectDetectionIsolateSendPort != null && !_isDisposed) {
            _objectDetectionIsolateSendPort!.send(payload);
        } else {
            _isWaitingForDetection = false;
        }
        _pendingImageDataBytes = null;
      } else {
        if (!_isWaitingForDetection && _isBusy) {
          if (mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
        }
      }
    } else if (message is List && message.length == 2 && message[0].toString().startsWith('Error from RotationIsolate')) {
      print('****** Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false; _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) {
         if (mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    } else {
      print('RealtimeObjectDetectionScreen: Unexpected msg from RotationIsolate: ${message.runtimeType}');
      _isWaitingForRotation = false; _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) {
          if (mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_isDisposed) return;
    print("RealtimeObjectDetectionScreen: Initializing camera: ${cameraDescription.name}");

    if (_cameraController != null) {
      await _stopCameraStream();
      await _cameraController!.dispose();
      _cameraController = null;
    }

    if (mounted && !_isDisposed) setState(() { _isCameraInitialized = false; });

    final newController = CameraController(
      cameraDescription, ResolutionPreset.high, enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await newController.initialize();
      if (_isDisposed) { await newController.dispose(); return; }
      _cameraController = newController;
      print("RealtimeObjectDetectionScreen: CameraController initialized: ${cameraDescription.name}");

      if ((_cameraController?.value.aspectRatio ?? 0) <= 0) {
          throw CameraException("Invalid AspectRatio", "Ratio is zero or negative.");
      }
      await _startCameraStream();
      if (mounted && !_isDisposed) {
        setState(() {
          _isCameraInitialized = true;
          _cameraIndex = widget.cameras.indexOf(cameraDescription);
        });
      }
    } catch (e) {
      print('****** Camera init error for ${cameraDescription.name}: $e');
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('카메라 초기화 오류: $e')));
        setState(() => _isCameraInitialized = false);
      }
      await newController.dispose(); // 실패 시 컨트롤러 해제
    }
  }

  Future<void> _startCameraStream() async {
    if (_isDisposed || _cameraController == null || !_cameraController!.value.isInitialized || _cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.startImageStream(_processCameraImage);
      print("RealtimeObjectDetectionScreen: Camera stream started.");
       if (mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
    } catch (e) {
      print('****** Start stream error: $e');
      if (mounted && !_isDisposed) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('스트림 시작 오류: $e')));
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || !_cameraController!.value.isStreamingImages) {
      _isBusy = false; return;
    }
    try {
      await _cameraController!.stopImageStream();
      print("RealtimeObjectDetectionScreen: Camera stream stopped.");
    } catch (e) {
      print('****** Stop stream error: $e');
    } finally {
      _isBusy = false; _isWaitingForRotation = false; _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isDisposed || !mounted || _isBusy || _imageRotationIsolateSendPort == null) return;
    
    _isBusy = true; _isWaitingForRotation = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) { allBytes.putUint8List(plane.bytes); }
      _pendingImageDataBytes = allBytes.done().buffer.asUint8List();
      _pendingImageDataWidth = image.width; _pendingImageDataHeight = image.height;
      _pendingImageDataFormatRaw = image.format.raw;
      _pendingImageDataBytesPerRow = image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0;
      _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

      final camera = widget.cameras[_cameraIndex];
      // 화면 방향 감지는 실제 앱에서는 더 정확한 방법이 필요합니다. (예: OrientationBuilder 또는 native 연동)
      // 테스트 및 단순화를 위해 PortraitUp으로 가정합니다.
      final DeviceOrientation deviceRotation = DeviceOrientation.portraitUp;

      final Map<String, dynamic> rotationPayload = {
        'sensorOrientation': camera.sensorOrientation,
        'deviceOrientationIndex': deviceRotation.index,
      };

      if (_imageRotationIsolateSendPort != null && !_isDisposed) {
        _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
        _pendingImageDataBytes = null; _isWaitingForRotation = false; _isBusy = false;
      }
    } catch (e) {
      print('****** Error processing image: $e');
      _pendingImageDataBytes = null; _isWaitingForRotation = false; _isBusy = false;
    }
  }

  void _switchCamera() {
    if (_isDisposed || widget.cameras.length < 2 || _isBusy) return;
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    Future.microtask(() async {
        if (_isDisposed) return;
        await _stopCameraStream();
        if (!_isDisposed && mounted) {
            await _initializeCamera(widget.cameras[newIndex]);
        }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('실시간 객체 탐지'), actions: _appBarActions()),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(), const SizedBox(height: 10),
            Text(widget.cameras.isEmpty ? '카메라 없음' : '카메라 초기화 중...'),
          ]),
        ),
      );
    }

    final double cameraAspectRatio = _cameraController!.value.aspectRatio > 0 ? _cameraController!.value.aspectRatio : 16.0 / 9.0;

    return Scaffold(
      appBar: AppBar(title: const Text('실시간 객체 탐지'), actions: _appBarActions()),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final Size parentSize = constraints.biggest;
            double previewWidth, previewHeight;
            if (parentSize.isEmpty || cameraAspectRatio <= 0) {
              previewWidth = parentSize.width; previewHeight = parentSize.height;
            } else if (parentSize.width / parentSize.height > cameraAspectRatio) {
              previewHeight = parentSize.height; previewWidth = previewHeight * cameraAspectRatio;
            } else {
              previewWidth = parentSize.width; previewHeight = previewWidth / cameraAspectRatio;
            }
            previewWidth = previewWidth.clamp(0.0, parentSize.width);
            previewHeight = previewHeight.clamp(0.0, parentSize.height);

            return Stack(
              fit: StackFit.expand, alignment: Alignment.center,
              children: [
                if (previewWidth > 0 && previewHeight > 0)
                  Center(child: SizedBox(width: previewWidth, height: previewHeight, child: CameraPreview(_cameraController!)))
                else
                  const Center(child: Text("카메라 미리보기 크기 오류")),
                if (_detectedObjects.isNotEmpty && _lastImageSize != null && _imageRotation != null)
                  CustomPaint(
                    size: parentSize,
                    painter: ObjectPainter(
                      objects: _detectedObjects, imageSize: _lastImageSize!, screenSize: parentSize,
                      rotation: _imageRotation!, cameraLensDirection: widget.cameras[_cameraIndex].lensDirection,
                      cameraPreviewAspectRatio: cameraAspectRatio,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget>? _appBarActions() {
    if (widget.cameras.length < 2) return null;
    return [
      IconButton(
        icon: Icon(
          (_cameraController != null && _cameraController!.value.isInitialized)
              ? (widget.cameras[_cameraIndex].lensDirection == CameraLensDirection.front
                  ? Icons.camera_front
                  : Icons.camera_rear)
              : Icons.camera_rear,
        ),
        onPressed: _isBusy ? null : _switchCamera,
        tooltip: '카메라 전환',
      ),
    ];
  }
}