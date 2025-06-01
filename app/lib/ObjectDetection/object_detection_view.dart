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

enum ObjectSizeCategory { small, medium, large, unknown }
enum HorizontalPositionCategory { left, center, right, unknown }

class DetectedObjectInfo {
  final DetectedObject object;
  final ObjectSizeCategory sizeCategory;
  final HorizontalPositionCategory horizontalPosition;
  final Rect boundingBox;
  final String? label;

  DetectedObjectInfo({
    required this.object,
    required this.sizeCategory,
    required this.horizontalPosition,
    required this.boundingBox,
    this.label,
  });

  String get sizeDescription {
    switch (sizeCategory) {
      case ObjectSizeCategory.small:
        return "작은";
      case ObjectSizeCategory.medium:
        return "중간 크기의";
      case ObjectSizeCategory.large:
        return "큰";
      default:
        return "";
    }
  }

  String get horizontalLocationDescription {
    switch (horizontalPosition) {
      case HorizontalPositionCategory.left:
        return "왼쪽에";
      case HorizontalPositionCategory.center:
        return "중앙에";
      case HorizontalPositionCategory.right:
        return "오른쪽에";
      default:
        return "";
    }
  }
}


class ObjectDetectionView extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(List<DetectedObjectInfo> objectsInfo)? onObjectsDetected;
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
  List<DetectedObjectInfo> _processedObjects = [];
  InputImageRotation? _imageRotation;
  late ObjectDetector _objectDetector;
  Size? _lastImageSize;
  Size? _screenSize;

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
      if (mounted && !_isDisposed) {
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
    if (_isDisposed) {
      print("****** ObjectDetectionView: Already disposed.");
      return;
    }
    _isDisposed = true;

    Future.microtask(() async {
      // 1. Stop camera stream first
      await _stopCameraStream();
      print("****** ObjectDetectionView: Camera stream stopped.");

      // 2. Signal isolates to shut down
      _killIsolates(); // This will attempt to send 'shutdown' or kill directly
      print("****** ObjectDetectionView: Shutdown signal processed for isolates.");

      // 3. Brief delay to allow isolates to process shutdown and send ack.
      await Future.delayed(const Duration(milliseconds: 250)); // Increased delay slightly

      // 4. Cancel subscriptions
      await _objectDetectionSubscription?.cancel();
      _objectDetectionSubscription = null;
      await _imageRotationSubscription?.cancel();
      _imageRotationSubscription = null;
      print("****** ObjectDetectionView: Subscriptions cancelled.");

      // 5. Close receive ports
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
      
      // 6. Dispose CameraController
      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error disposing CameraController: $e\n$stacktrace');
      }
      _cameraController = null;

      // 7. Close ObjectDetector (main isolate's instance)
      try {
        await _objectDetector.close();
        print("****** ObjectDetectionView: Main ObjectDetector closed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error closing main ObjectDetector: $e\n$stacktrace');
      }
      
      // 8. Nullify isolate and sendport references as a final cleanup
      _objectDetectionIsolate = null;
      _imageRotationIsolate = null;
      _objectDetectionIsolateSendPort = null;
      _imageRotationIsolateSendPort = null;
      print("****** ObjectDetectionView: Isolate and SendPort references nulled.");
    });

    super.dispose();
    print("****** ObjectDetectionView: super.dispose() completed.");
  }

  Future<bool> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn isolates.");
      if (mounted && !_isDisposed) {
         setState(() {
             _initializationErrorMsg = "백그라운드 작업 토큰 초기화 실패.";
         });
      }
      return false;
    }

    try {
      _objectDetectionReceivePort = ReceivePort();
      _objectDetectionIsolate = await Isolate.spawn(
          detectObjectsIsolateEntry,
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
      if(mounted && !_isDisposed) {
        setState(() {
           _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
        });
      }
      return false;
    }
  }

  void _killIsolates() {
    // Signal detection isolate
    if (_objectDetectionIsolateSendPort != null && _objectDetectionIsolate != null) {
        if (!_isDisposed) { // Check _isDisposed before sending
            try {
              _objectDetectionIsolateSendPort!.send('shutdown');
              print("****** ObjectDetectionView: Sent 'shutdown' to DetectionIsolate.");
            } catch (e) {
              print("****** ObjectDetectionView: Error sending 'shutdown' to DetectionIsolate: $e. Killing directly.");
              _objectDetectionIsolate?.kill(priority: Isolate.immediate);
            }
        } else { // If disposed, just kill
             _objectDetectionIsolate?.kill(priority: Isolate.immediate);
        }
    } else if (_objectDetectionIsolate != null) { 
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      print("****** ObjectDetectionView: DetectionIsolate killed directly (no SendPort or already disposed path).");
    }
    // Do not null SendPort here, let dispose microtask handle it after delay and subscription cancellation

    // Signal rotation isolate
    if (_imageRotationIsolateSendPort != null && _imageRotationIsolate != null) {
        if (!_isDisposed) { // Check _isDisposed before sending
            try {
              _imageRotationIsolateSendPort!.send('shutdown');
              print("****** ObjectDetectionView: Sent 'shutdown' to RotationIsolate.");
            } catch (e) {
              print("****** ObjectDetectionView: Error sending 'shutdown' to RotationIsolate: $e. Killing directly.");
              _imageRotationIsolate?.kill(priority: Isolate.immediate);
            }
        } else { // If disposed, just kill
            _imageRotationIsolate?.kill(priority: Isolate.immediate);
        }
    } else if (_imageRotationIsolate != null) {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      print("****** ObjectDetectionView: RotationIsolate killed directly (no SendPort or already disposed path).");
    }
    // Do not null SendPort here
  }

  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_detection') {
        print("****** ObjectDetectionView: Detection isolate acknowledged shutdown. Killing now.");
        _objectDetectionIsolate?.kill(priority: Isolate.immediate);
        _objectDetectionIsolate = null;
        _objectDetectionIsolateSendPort = null; // Null out send port on ack
        return;
    }

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
    } else if (message is List<DetectedObject>) {
      List<DetectedObjectInfo> newProcessedObjects = [];

      if (message.isNotEmpty && _lastImageSize != null && _screenSize != null && _imageRotation != null && _cameraController != null  && _cameraController!.value.isInitialized) {
        DetectedObject largestMlKitObject = message.reduce((curr, next) {
          final double areaCurr = curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext = next.boundingBox.width * next.boundingBox.height;
          return areaCurr > areaNext ? curr : next;
        });

        final Rect displayRect = _calculateDisplayRect(
          mlKitBoundingBox: largestMlKitObject.boundingBox,
          originalImageSize: _lastImageSize!,
          canvasSize: _screenSize!,
          imageRotation: _imageRotation!,
          cameraLensDirection: widget.cameras[_cameraIndex].lensDirection,
          cameraPreviewAspectRatio: _cameraController!.value.aspectRatio,
        );

        ObjectSizeCategory sizeCategory = ObjectSizeCategory.unknown;
        HorizontalPositionCategory horizontalPosition = HorizontalPositionCategory.unknown;

        if (_screenSize!.width > 0 && _screenSize!.height > 0) {
            final double screenArea = _screenSize!.width * _screenSize!.height;
            final double objectArea = displayRect.width * displayRect.height;
            if (screenArea > 0) {
                final double areaRatio = objectArea / screenArea;
                if (areaRatio > 0.20) {
                    sizeCategory = ObjectSizeCategory.large;
                } else if (areaRatio > 0.05) {
                    sizeCategory = ObjectSizeCategory.medium;
                } else if (areaRatio > 0.005) { 
                    sizeCategory = ObjectSizeCategory.small;
                }
            }
            final objectCenterX = displayRect.left + displayRect.width / 2;
            final screenThird = _screenSize!.width / 3;
            if (objectCenterX < screenThird) {
              horizontalPosition = HorizontalPositionCategory.left;
            } else if (objectCenterX > screenThird * 2) {
              horizontalPosition = HorizontalPositionCategory.right;
            } else {
              horizontalPosition = HorizontalPositionCategory.center;
            }
        }
        
        final String? mainLabel = largestMlKitObject.labels.isNotEmpty ? largestMlKitObject.labels.first.text : null;

        newProcessedObjects.add(DetectedObjectInfo(
          object: largestMlKitObject,
          sizeCategory: sizeCategory,
          horizontalPosition: horizontalPosition,
          boundingBox: displayRect,
          label: mainLabel,
        ));
      }

      _isWaitingForDetection = false;
      if (mounted && !_isDisposed) {
        setState(() {
          _processedObjects = newProcessedObjects;
        });
      }
      widget.onObjectsDetected?.call(newProcessedObjects);

      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().contains('Error')) {
      print('****** ObjectDetectionView: Detection Isolate Error: ${message[1]}');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! List<DetectedObject>)) {
      print('****** ObjectDetectionView: Detection Isolate exited or sent empty/null message ($message). Handling as potential isolate death.');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
      _objectDetectionIsolate = null; 
      _objectDetectionIsolateSendPort = null;
    } else {
      print('****** ObjectDetectionView: Unexpected message from Detection Isolate: ${message.runtimeType} - $message');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    }
  }

  Rect _calculateDisplayRect({
    required Rect mlKitBoundingBox,
    required Size originalImageSize,
    required Size canvasSize,
    required InputImageRotation imageRotation,
    required CameraLensDirection cameraLensDirection,
    required double cameraPreviewAspectRatio,
  }) {
    if (originalImageSize.isEmpty || canvasSize.isEmpty || cameraPreviewAspectRatio <= 0) {
      return Rect.zero;
    }

    Rect cameraViewRect;
    final double screenAspectRatio = canvasSize.width / canvasSize.height;

    if (screenAspectRatio > cameraPreviewAspectRatio) {
      final double fittedHeight = canvasSize.height;
      final double fittedWidth = fittedHeight * cameraPreviewAspectRatio;
      final double offsetX = (canvasSize.width - fittedWidth) / 2;
      cameraViewRect = Rect.fromLTWH(offsetX, 0, fittedWidth, fittedHeight);
    } else {
      final double fittedWidth = canvasSize.width;
      final double fittedHeight = fittedWidth / cameraPreviewAspectRatio;
      final double offsetY = (canvasSize.height - fittedHeight) / 2;
      cameraViewRect = Rect.fromLTWH(0, offsetY, fittedWidth, fittedHeight);
    }

    final bool isImageRotatedSideways =
        imageRotation == InputImageRotation.rotation90deg ||
            imageRotation == InputImageRotation.rotation270deg;

    final double mlImageWidth = isImageRotatedSideways ? originalImageSize.height : originalImageSize.width;
    final double mlImageHeight = isImageRotatedSideways ? originalImageSize.width : originalImageSize.height;

    if (mlImageWidth == 0 || mlImageHeight == 0) return Rect.zero;

    final double scaleX = cameraViewRect.width / mlImageWidth;
    final double scaleY = cameraViewRect.height / mlImageHeight;

    double l, t, r, b;

    switch (imageRotation) {
      case InputImageRotation.rotation0deg:
        l = mlKitBoundingBox.left * scaleX;
        t = mlKitBoundingBox.top * scaleY;
        r = mlKitBoundingBox.right * scaleX;
        b = mlKitBoundingBox.bottom * scaleY;
        break;
      case InputImageRotation.rotation90deg:
        l = mlKitBoundingBox.top * scaleX;
        t = (mlImageHeight - mlKitBoundingBox.right) * scaleY; 
        r = mlKitBoundingBox.bottom * scaleX;
        b = (mlImageHeight - mlKitBoundingBox.left) * scaleY;  
        break;
      case InputImageRotation.rotation180deg:
        l = (mlImageWidth - mlKitBoundingBox.right) * scaleX;
        t = (mlImageHeight - mlKitBoundingBox.bottom) * scaleY;
        r = (mlImageWidth - mlKitBoundingBox.left) * scaleX;
        b = (mlImageHeight - mlKitBoundingBox.top) * scaleY;
        break;
      case InputImageRotation.rotation270deg:
        l = (mlImageWidth - mlKitBoundingBox.bottom) * scaleX; 
        t = mlKitBoundingBox.left * scaleY;
        r = (mlImageWidth - mlKitBoundingBox.top) * scaleX;   
        b = mlKitBoundingBox.right * scaleY;
        break;
    }
    
    if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
       if (imageRotation == InputImageRotation.rotation0deg || imageRotation == InputImageRotation.rotation180deg) {
         final double tempL = l;
         l = cameraViewRect.width - r;
         r = cameraViewRect.width - tempL;
       }
    }

    Rect displayRect = Rect.fromLTRB(
        cameraViewRect.left + l,
        cameraViewRect.top + t,
        cameraViewRect.left + r,
        cameraViewRect.top + b);

    return Rect.fromLTRB(
      displayRect.left.clamp(cameraViewRect.left, cameraViewRect.right),
      displayRect.top.clamp(cameraViewRect.top, cameraViewRect.bottom),
      displayRect.right.clamp(cameraViewRect.left, cameraViewRect.right),
      displayRect.bottom.clamp(cameraViewRect.top, cameraViewRect.bottom),
    );
  }

  void _handleRotationResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_rotation') {
        print("****** ObjectDetectionView: Rotation isolate acknowledged shutdown. Killing now.");
        _imageRotationIsolate?.kill(priority: Isolate.immediate);
        _imageRotationIsolate = null;
        _imageRotationIsolateSendPort = null; // Null out send port on ack
        return;
    }

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
      print("****** ObjectDetectionView: ImageRotationIsolate SendPort received.");
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;
      _imageRotation = message; 

      if (_pendingImageDataBytes != null && _objectDetectionIsolateSendPort != null && message != null) {
        _isWaitingForDetection = true;
        final Map<String, dynamic> payload = {
          'bytes': _pendingImageDataBytes!,
          'width': _pendingImageDataWidth!,
          'height': _pendingImageDataHeight!,
          'rotation': message, 
          'formatRaw': _pendingImageDataFormatRaw!,
          'bytesPerRow': _pendingImageDataBytesPerRow!,
        };
        if (!_isDisposed && _objectDetectionIsolateSendPort != null) {
             _objectDetectionIsolateSendPort!.send(payload);
        } else {
          print("****** ObjectDetectionView: Not sending to detection isolate (disposed or no sendPort for detection)");
           _isWaitingForDetection = false; 
        }
        _pendingImageDataBytes = null; 
      } else {
         _pendingImageDataBytes = null; 
        if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().contains('Error')) {
      print('****** ObjectDetectionView: Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! InputImageRotation)) {
      print('****** ObjectDetectionView: Rotation Isolate exited or sent empty/null message ($message). Handling as potential isolate death.');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      _imageRotationIsolate = null;
      _imageRotationIsolateSendPort = null;
    } else {
      print('****** ObjectDetectionView: Unexpected message from Rotation Isolate: ${message.runtimeType} - $message');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_isDisposed) return;
    if (_cameraController != null) {
      await _stopCameraStream(); 
      await _cameraController!.dispose();
      _cameraController = null;
      print("****** ObjectDetectionView: Old CameraController disposed before new init for ${cameraDescription.name}.");
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
          _initializationErrorMsg = "카메라 시작에 실패했습니다.\n권한 확인 또는 앱 재시작 필요.\n오류: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
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
             _initializationErrorMsg = "카메라 스트림 시작 실패: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
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

      _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

      final camera = widget.cameras[_cameraIndex];
      final orientation = _currentDeviceOrientation ?? MediaQuery.of(context).orientation;
      
      final DeviceOrientation deviceRotation = (orientation == Orientation.landscape)
          ? (Platform.isIOS ? DeviceOrientation.landscapeRight : DeviceOrientation.landscapeLeft)
          : DeviceOrientation.portraitUp;
      
      final Map<String, dynamic> rotationPayload = {
        'sensorOrientation': camera.sensorOrientation,
        'deviceOrientationIndex': deviceRotation.index,
      };

      if (!_isDisposed && _imageRotationIsolateSendPort != null) { 
         _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
         print("****** ObjectDetectionView: Not sending to rotation isolate (disposed or no sendPort for rotation)");
         _pendingImageDataBytes = null; 
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
        await _stopCameraStream(); 
        if (!_isDisposed && mounted) { 
            await _initializeCamera(widget.cameras[newIndex]); 
        }
    });
  }

  @override
  Widget build(BuildContext context) {
    _currentDeviceOrientation = MediaQuery.of(context).orientation;

    if (_initializationErrorMsg != null) {
      return Center( child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_initializationErrorMsg!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
        )
      );
    }

    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return Center( child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(widget.cameras.isEmpty ? '카메라 없음' : '카메라 초기화 중...'),
          ],
        ));
    }

    final double cameraAspectRatio = _cameraController!.value.aspectRatio;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _screenSize = constraints.biggest;
        final Size parentSize = _screenSize!; 
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
            if (_processedObjects.isNotEmpty && _lastImageSize != null && _imageRotation != null && _screenSize != null)
              CustomPaint(
                size: parentSize, 
                painter: ObjectPainter(
                  objects: _processedObjects.map((info) => info.object).toList(),
                  imageSize: _lastImageSize!,
                  screenSize: _screenSize!, 
                  rotation: _imageRotation!,
                  cameraLensDirection: widget.cameras[_cameraIndex].lensDirection,
                  cameraPreviewAspectRatio: cameraAspectRatio,
                  showNameTags: false, 
                ),
              ),
          ],
        );
      },
    );
  }
}