// File: lib/ObjectDetection/object_detection_view.dart
import 'dart:async';
import 'dart:io'; // For Platform
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For RootIsolateToken, DeviceOrientation
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import './camera_screen.dart' show IsolateDataHolder;
import './mlkit_object_detection.dart';
import './object_painter.dart';


enum ObjectSizeCategory { small, medium, large, unknown }

class DetectedObjectInfo {
  final DetectedObject object;
  final ObjectSizeCategory sizeCategory;
  final Rect boundingBox; // 화면상의 바운딩 박스
  final String? label; // ML Kit에서 제공하는 원본 레이블
  final String positionalDescription; // "좌측 전방", "전방", "우측 전방"

  DetectedObjectInfo({
    required this.object,
    required this.sizeCategory,
    required this.boundingBox,
    this.label,
    required this.positionalDescription,
  });

  String get sizeDescription {
    switch (sizeCategory) {
      case ObjectSizeCategory.small:
        return "작은";
      case ObjectSizeCategory.medium:
        return "중간";
      case ObjectSizeCategory.large:
        return "큰";
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
  ObjectDetector? _objectDetector;
  Size? _lastImageSize;
  Size? _screenSize; // 화면 크기 저장

  Isolate? _objectDetectionIsolate;
  Isolate? _imageRotationIsolate;
  ReceivePort? _objectDetectionReceivePort;
  ReceivePort? _imageRotationReceivePort;
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
  bool _isolatesShuttingDown = false;

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    print("ObjectDetectionView: initState");
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
      if (!success && mounted && !_isDisposed) {
          setState(() {
            _initializationErrorMsg = "백그라운드 작업 초기화에 실패했습니다.";
          });
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
    _isDisposed = true;
    print("****** ObjectDetectionView: Dispose called. _isDisposed set to true.");

    Future.microtask(() async {
      print("****** ObjectDetectionView: Dispose microtask initiated.");

      await _stopCameraStream();
      print("****** ObjectDetectionView: Camera stream stopped.");

      await _objectDetectionSubscription?.cancel();
      _objectDetectionSubscription = null;
      await _imageRotationSubscription?.cancel();
      _imageRotationSubscription = null;
      print("****** ObjectDetectionView: Stream subscriptions cancelled.");
      
      await _shutdownIsolates();
      print("****** ObjectDetectionView: Isolates shutdown process completed.");

      _objectDetectionReceivePort?.close();
      _objectDetectionReceivePort = null;
      _imageRotationReceivePort?.close();
      _imageRotationReceivePort = null;
      print("****** ObjectDetectionView: Receive ports closed.");

      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error disposing CameraController: $e\n$stacktrace');
      }
      _cameraController = null;

      try {
        await _objectDetector?.close();
        print("****** ObjectDetectionView: Main ObjectDetector closed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error closing main ObjectDetector: $e\n$stacktrace');
      }
      _objectDetector = null;

       print("****** ObjectDetectionView: All resources cleaned up in dispose microtask.");
    });

    super.dispose();
    print("****** ObjectDetectionView: super.dispose() completed.");
  }

  Future<bool> _spawnIsolates() async {
    if (_isDisposed) return false;
    _isolatesShuttingDown = false;

    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn isolates.");
      return false;
    }

    try {
      _objectDetectionReceivePort = ReceivePort();
      _objectDetectionIsolate = await Isolate.spawn(
          detectObjectsIsolateEntry, 
          IsolateDataHolder(_objectDetectionReceivePort!.sendPort, rootIsolateToken), 
          onError: _objectDetectionReceivePort!.sendPort,
          onExit: _objectDetectionReceivePort!.sendPort, 
          debugName: "ObjectDetectionIsolate_View");
      _objectDetectionSubscription = _objectDetectionReceivePort!.listen(_handleDetectionResult);
      print("****** ObjectDetectionView: ObjectDetectionIsolate spawned.");

      _imageRotationReceivePort = ReceivePort();
      _imageRotationIsolate = await Isolate.spawn(
          getImageRotationIsolateEntry, 
          _imageRotationReceivePort!.sendPort, 
          onError: _imageRotationReceivePort!.sendPort,
          onExit: _imageRotationReceivePort!.sendPort,
          debugName: "ImageRotationIsolate_View");
      _imageRotationSubscription = _imageRotationReceivePort!.listen(_handleRotationResult);
      print("****** ObjectDetectionView: ImageRotationIsolate spawned.");
      return true;
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Failed to spawn isolates: $e\n$stacktrace");
       if (mounted && !_isDisposed) {
          setState(() {
            _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
          });
       }
      return false;
    }
  }

  Future<void> _shutdownIsolates() async {
    if (_isolatesShuttingDown) return;
    _isolatesShuttingDown = true;
    print("****** ObjectDetectionView: Attempting to gracefully shutdown isolates...");

    if (_objectDetectionIsolateSendPort != null && _objectDetectionIsolate != null) {
        try {
            _objectDetectionIsolateSendPort!.send('shutdown');
            print("****** ObjectDetectionView: Sent 'shutdown' to DetectionIsolate.");
        } catch (e) {
            print("****** ObjectDetectionView: Error sending shutdown to DetectionIsolate: $e. Killing directly.");
            _objectDetectionIsolate?.kill(priority: Isolate.immediate);
        }
    } else {
        _objectDetectionIsolate?.kill(priority: Isolate.immediate);
    }
    
    if (_imageRotationIsolateSendPort != null && _imageRotationIsolate != null) {
        try {
            _imageRotationIsolateSendPort!.send('shutdown');
            print("****** ObjectDetectionView: Sent 'shutdown' to RotationIsolate.");
        } catch (e) {
            print("****** ObjectDetectionView: Error sending shutdown to RotationIsolate: $e. Killing directly.");
            _imageRotationIsolate?.kill(priority: Isolate.immediate);
        }
    } else {
        _imageRotationIsolate?.kill(priority: Isolate.immediate);
    }

    await Future.delayed(const Duration(milliseconds: 300)); 

    print("****** ObjectDetectionView: Proceeding to nullify isolate resources.");
    _objectDetectionIsolate?.kill(priority: Isolate.immediate); 
    _objectDetectionIsolate = null;
    _objectDetectionIsolateSendPort = null;

    _imageRotationIsolate?.kill(priority: Isolate.immediate); 
    _imageRotationIsolate = null;
    _imageRotationIsolateSendPort = null;
    
    print("****** ObjectDetectionView: Isolates assumed terminated and resources nulled.");
    _isolatesShuttingDown = false;
  }


  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted || _isolatesShuttingDown) return;

    if (message == 'isolate_shutdown_ack_detection') {
        print("****** ObjectDetectionView: Detection isolate acknowledged shutdown. It should self-terminate.");
        return;
    }
    
    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
      return; 
    }
    
    List<DetectedObjectInfo> newProcessedObjects = [];
    if (message is List<DetectedObject>) {
      if (message.isNotEmpty && _lastImageSize != null && _screenSize != null && _imageRotation != null && _cameraController != null && _cameraController!.value.isInitialized) {
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
        }
        
        final String? mainLabel = largestMlKitObject.labels.isNotEmpty ? largestMlKitObject.labels.first.text : null;

        // MODIFIED: Determine positional description based on occupancy
        String positionalDescription = "전방"; // Default
        if (_screenSize != null && _screenSize!.width > 0 && !displayRect.isEmpty) {
            final double screenWidth = _screenSize!.width;
            final double screenHeight = _screenSize!.height; 
            final double screenThird = screenWidth / 3;

            final Rect leftSectionRect = Rect.fromLTWH(0, 0, screenThird, screenHeight);
            final Rect middleSectionRect = Rect.fromLTWH(screenThird, 0, screenThird, screenHeight);
            final Rect rightSectionRect = Rect.fromLTWH(screenThird * 2, 0, screenThird, screenHeight);

            final Rect intersectionLeft = displayRect.intersect(leftSectionRect);
            final Rect intersectionMiddle = displayRect.intersect(middleSectionRect);
            final Rect intersectionRight = displayRect.intersect(rightSectionRect);

            final double areaLeft = (intersectionLeft.width < 0 || intersectionLeft.height < 0) ? 0 : intersectionLeft.width * intersectionLeft.height;
            final double areaMiddle = (intersectionMiddle.width < 0 || intersectionMiddle.height < 0) ? 0 : intersectionMiddle.width * intersectionMiddle.height;
            final double areaRight = (intersectionRight.width < 0 || intersectionRight.height < 0) ? 0 : intersectionRight.width * intersectionRight.height;
            
            if (areaLeft == 0 && areaMiddle == 0 && areaRight == 0 && !displayRect.isEmpty) {
                 // If no intersection but object exists, determine by center (fallback)
                final double objectCenterX = displayRect.left + displayRect.width / 2;
                if (objectCenterX < screenThird) {
                    positionalDescription = "좌측 전방";
                } else if (objectCenterX < screenThird * 2) {
                    positionalDescription = "전방";
                } else {
                    positionalDescription = "우측 전방";
                }
            } else if (areaLeft > areaMiddle && areaLeft > areaRight) {
                positionalDescription = "좌측 전방";
            } else if (areaRight > areaLeft && areaRight > areaMiddle) {
                positionalDescription = "우측 전방";
            } else if (areaMiddle >= areaLeft && areaMiddle >= areaRight && areaMiddle > 0) {
                 positionalDescription = "전방";
            } else {
                // Fallback for ambiguous cases or if all areas are zero but object is somehow present
                // (could happen if object is tiny or calculations are imperfect)
                // For safety, default to "전방" if an object is detected but position is unclear.
                 final double objectCenterX = displayRect.left + displayRect.width / 2;
                if (objectCenterX < screenThird) {
                    positionalDescription = "좌측 전방";
                } else if (objectCenterX < screenThird * 2) {
                    positionalDescription = "전방";
                } else {
                    positionalDescription = "우측 전방";
                }
            }
        }


        newProcessedObjects.add(DetectedObjectInfo(
          object: largestMlKitObject,
          sizeCategory: sizeCategory,
          boundingBox: displayRect,
          label: mainLabel, // Store original label if needed for other purposes
          positionalDescription: positionalDescription, 
        ));
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().startsWith('Error from DetectionIsolate')) {
      print('****** ObjectDetectionView: Received error from Detection Isolate: ${message[1]}');
    } else if (message == null || (message is List && message.isEmpty && message is! List<DetectedObject>)) { 
      print('****** ObjectDetectionView: Detection Isolate exited or sent empty/null message. Message: $message');
    } else {
      print('****** ObjectDetectionView: Unexpected message from Detection Isolate: ${message.runtimeType} - $message');
    }

    _isWaitingForDetection = false;
    if (mounted && !_isDisposed) {
      setState(() {
        _processedObjects = newProcessedObjects;
      });
       widget.onObjectsDetected?.call(newProcessedObjects);
    }


    if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
       if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
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
    if (_isDisposed || !mounted || _isolatesShuttingDown) return;
    
    if (message == 'isolate_shutdown_ack_rotation') {
        print("****** ObjectDetectionView: Rotation isolate acknowledged shutdown. It should self-terminate.");
        return;
    }

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
      print("****** ObjectDetectionView: ImageRotationIsolate SendPort received.");
      return;
    }
    
    if (message is InputImageRotation?) {
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
          print("****** ObjectDetectionView: Not sending to detection isolate (disposed or no sendPort)");
           _isWaitingForDetection = false;
        }
        _pendingImageDataBytes = null;
      } else {
        if (!_isWaitingForDetection && _isBusy) {
             if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
        }
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().startsWith('Error from RotationIsolate')) {
      print('****** ObjectDetectionView: Received error from Rotation Isolate: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) {
          if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    } else if (message == null || (message is List && message.isEmpty && message is! InputImageRotation)) {
       print('****** ObjectDetectionView: Rotation Isolate exited or sent empty/null message. Message: $message');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) {
          if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    } else {
      print('****** ObjectDetectionView: Unexpected message from Rotation Isolate: ${message.runtimeType} - $message');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) {
          if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_isDisposed) {
        print("****** ObjectDetectionView: Attempted to initialize camera after dispose.");
        return;
    }
    print("****** ObjectDetectionView: Initializing camera: ${cameraDescription.name}");
    if (_cameraController != null) {
      print("****** ObjectDetectionView: Disposing existing camera controller before new init.");
      await _stopCameraStream(); 
      await _cameraController!.dispose();
      _cameraController = null;
      print("****** ObjectDetectionView: Old CameraController disposed.");
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
      print("****** ObjectDetectionView: New CameraController initialized for ${cameraDescription.name}. AspectRatio: ${_cameraController!.value.aspectRatio}");
      
      if (_cameraController!.value.aspectRatio <= 0) {
          throw CameraException("Invalid Camera AspectRatio", "Aspect ratio is zero or negative, cannot proceed.");
      }

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
    if (_isDisposed || _cameraController == null || !_cameraController!.value.isInitialized || _cameraController!.value.isStreamingImages) {
        print("****** ObjectDetectionView: Start stream skipped. Disposed: $_isDisposed, Controller: ${_cameraController == null}, Initialized: ${_cameraController?.value.isInitialized}, Streaming: ${_cameraController?.value.isStreamingImages}");
        return;
    }
    try {
      await _cameraController!.startImageStream(_processCameraImage);
      print("****** ObjectDetectionView: Camera stream started for ${_cameraController?.description.name}.");
        if (mounted && !_isDisposed) { 
            setState(() { _isBusy = false; }); 
        } else {
            _isBusy = false;
        }
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
    print("****** ObjectDetectionView: Attempting to stop camera stream.");
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print("****** ObjectDetectionView: CameraController is null or not initialized in _stopCameraStream. Skipping stop stream.");
        _isBusy = false; 
        return;
    }
    if (!_cameraController!.value.isStreamingImages) {
        print("****** ObjectDetectionView: Camera is not streaming in _stopCameraStream. Skipping stop stream.");
        _isBusy = false;
        return;
    }
    
    try {
      await _cameraController!.stopImageStream();
      print("****** ObjectDetectionView: Camera stream stopped successfully in _stopCameraStream for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Stop stream error in _stopCameraStream: $e\n$stacktrace');
    } finally {
         _isBusy = false; 
         _isWaitingForRotation = false;
         _isWaitingForDetection = false;
         _pendingImageDataBytes = null;
        print("****** ObjectDetectionView: Processing flags reset after _stopCameraStream attempt.");
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isDisposed || !mounted || _isBusy || _imageRotationIsolateSendPort == null || _isolatesShuttingDown) {
      return;
    }
    
    if (mounted && !_isDisposed) { 
        setState(() { _isBusy = true; });
    } else {
         _isBusy = true; 
    }
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
      
      final Orientation currentContextOrientation = MediaQuery.of(context).orientation;
      final Orientation orientationToUse = _currentDeviceOrientation ?? currentContextOrientation;
      
      final DeviceOrientation deviceRotation = (orientationToUse == Orientation.landscape)
          ? (Platform.isIOS ? DeviceOrientation.landscapeRight : DeviceOrientation.landscapeLeft)
          : DeviceOrientation.portraitUp;
      
      final Map<String, dynamic> rotationPayload = {
        'sensorOrientation': camera.sensorOrientation,
        'deviceOrientationIndex': deviceRotation.index,
      };

      if (!_isDisposed && _imageRotationIsolateSendPort != null) { 
         _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
         print("****** ObjectDetectionView: Not sending to rotation isolate (disposed or no sendPort)");
         _pendingImageDataBytes = null; 
         _isWaitingForRotation = false;
         if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
      }
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Error processing image: $e\n$stacktrace");
      _pendingImageDataBytes = null;
      _isWaitingForRotation = false;
       if(mounted && !_isDisposed) setState(() => _isBusy = false); else _isBusy = false;
    }
  }

  void _switchCamera() {
    if (_isDisposed || widget.cameras.length < 2 || _isBusy) return;
    print("****** ObjectDetectionView: Switching camera...");
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    
    Future.microtask(() async {
        if (_isDisposed) return;
        await _stopCameraStream(); 
        if (mounted && !_isDisposed) { 
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

    final double cameraAspectRatio = _cameraController!.value.isInitialized && _cameraController!.value.aspectRatio > 0 
                                      ? _cameraController!.value.aspectRatio 
                                      : 16.0/9.0; 


    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _screenSize = constraints.biggest;
        final Size parentSize = constraints.biggest;
        double previewWidth;
        double previewHeight;

        if (parentSize.isEmpty) { 
            previewWidth = 0;
            previewHeight = 0;
        } else if (parentSize.width / parentSize.height > cameraAspectRatio) { 
          previewHeight = parentSize.height;
          previewWidth = previewHeight * cameraAspectRatio;
        } else {
          previewWidth = parentSize.width;
          previewHeight = previewWidth / cameraAspectRatio;
        }
        
        if (previewWidth <= 0 || previewHeight <= 0 && !parentSize.isEmpty) {
            previewWidth = parentSize.width; 
            previewHeight = parentSize.height;
        }


        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_cameraController!.value.isInitialized && previewWidth > 0 && previewHeight > 0)
                Center(
                child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: CameraPreview(_cameraController!),
                ),
                )
            else
                const Center(child: Text("카메라 미리보기를 로드할 수 없습니다.")),
            
            if (_processedObjects.isNotEmpty && 
                _lastImageSize != null && 
                _imageRotation != null && 
                _screenSize != null && 
                _cameraController!.value.isInitialized &&
                cameraAspectRatio > 0)
              CustomPaint(
                size: parentSize, 
                painter: ObjectPainter(
                  objects: _processedObjects.map((info) => info.object).toList(),
                  imageSize: _lastImageSize!,
                  screenSize: _screenSize!, 
                  rotation: _imageRotation!,
                  cameraLensDirection: widget.cameras[_cameraIndex].lensDirection,
                  cameraPreviewAspectRatio: cameraAspectRatio,
                  showNameTags: false, // NameTag는 계속 그리지 않음
                ),
              ),
          ],
        );
      },
    );
  }
}