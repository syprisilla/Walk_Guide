// syprisilla/walk_guide/Walk_Guide-6a291b2d27615ed276ef08f7956a8c04df5ca664/app/lib/ObjectDetection/object_detection_view.dart

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
import 'camera_screen.dart' show IsolateDataHolder;
import 'object_painter.dart';


enum ObjectSizeCategory { small, medium, large, unknown }

class DetectedObjectInfo {
  final DetectedObject object;
  final ObjectSizeCategory sizeCategory;
  final Rect boundingBox;
  final String? label;

  DetectedObjectInfo({
    required this.object,
    required this.sizeCategory,
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
  bool _isShuttingDownIsolates = false;

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
    print("****** ObjectDetectionView: Dispose called. Current state: _isDisposed: $_isDisposed, _isShuttingDownIsolates: $_isShuttingDownIsolates");
    if (_isDisposed) {
      print("****** ObjectDetectionView: Already disposed. Skipping further actions.");
      return;
    }
    _isDisposed = true;
    _isShuttingDownIsolates = true;
    print("****** ObjectDetectionView: Set _isDisposed=true, _isShuttingDownIsolates=true. Initiating cleanup.");

    // 1. 즉시 Isolate에 종료 신호 전송
    _sendShutdownSignalToIsolates();

    // 2. 비동기 정리 작업 예약 (카메라 및 기타 리소스)
    //    dispose() 자체는 동기적으로 완료되어야 하므로, 오래 걸리는 작업은 microtask로 분리
    Future.microtask(() async {
      print("****** ObjectDetectionView: Dispose microtask started.");

      // 2a. 카메라 스트림 중지 (가장 먼저 수행)
      if (_cameraController != null && _cameraController!.value.isInitialized && _cameraController!.value.isStreamingImages) {
        try {
          print("****** ObjectDetectionView: Attempting to stop image stream in microtask...");
          await _cameraController!.stopImageStream();
          print("****** ObjectDetectionView: Image stream stopped in microtask.");
        } catch (e, stacktrace) {
          print('****** ObjectDetectionView: Error stopping image stream in microtask: $e\n$stacktrace');
        }
      }
      // 스트림 중지 후 관련 플래그 즉시 초기화
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;

      // 2b. Isolate가 종료 신호를 처리할 시간 확보 (짧은 지연)
      // 이 시간 동안 Isolate는 'shutdown' 메시지를 받고 자체 리소스(ObjectDetector)를 닫고 ack를 보낼 수 있음
      await Future.delayed(const Duration(milliseconds: 250)); // 이전 300ms에서 약간 줄임

      // 2c. 구독 취소
      try {
        await _objectDetectionSubscription?.cancel();
        _objectDetectionSubscription = null;
        await _imageRotationSubscription?.cancel();
        _imageRotationSubscription = null;
        print("****** ObjectDetectionView: Subscriptions cancelled in microtask.");
      } catch (e) {
        print("****** ObjectDetectionView: Error cancelling subscriptions in microtask: $e");
      }
      
      // 2d. 수신 포트 닫기
      try {
        _objectDetectionReceivePort.close();
        print("****** ObjectDetectionView: Object detection receive port closed in microtask.");
      } catch (e) {
        print("****** ObjectDetectionView: Error closing object detection receive port in microtask: $e");
      }
      try {
        _imageRotationReceivePort.close();
        print("****** ObjectDetectionView: Image rotation receive port closed in microtask.");
      } catch (e) {
        print("****** ObjectDetectionView: Error closing image rotation receive port in microtask: $e");
      }

      // 2e. Isolate 강제 종료 (정상 종료되지 않은 경우 대비)
      _forceKillRemainingIsolates(); // 내부에서 로그 출력

      // 2f. 카메라 컨트롤러 해제
      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed in microtask.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error disposing CameraController in microtask: $e\n$stacktrace');
      }
      _cameraController = null; // 참조 제거

      // 2g. 메인 Isolate의 ObjectDetector 해제
      try {
        await _objectDetector.close();
        print("****** ObjectDetectionView: Main ObjectDetector closed in microtask.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error closing main ObjectDetector in microtask: $e\n$stacktrace');
      }
      print("****** ObjectDetectionView: Dispose microtask completed.");
    });

    super.dispose();
    print("****** ObjectDetectionView: super.dispose() completed.");
  }

  void _sendShutdownSignalToIsolates() {
    print("****** ObjectDetectionView: _sendShutdownSignalToIsolates called.");
    if (_objectDetectionIsolateSendPort != null) {
      try {
        print("****** ObjectDetectionView: Sending 'shutdown' to DetectionIsolate.");
        _objectDetectionIsolateSendPort!.send('shutdown');
      } catch (e) {
        print("****** ObjectDetectionView: Error sending 'shutdown' to DetectionIsolate: $e. Isolate might have already exited.");
        // Isolate가 이미 종료되었을 수 있으므로, 오류 발생 시 SendPort를 null로 설정하여 재시도 방지
        _objectDetectionIsolateSendPort = null;
      }
    } else {
      print("****** ObjectDetectionView: DetectionIsolateSendPort is null. Cannot send shutdown.");
    }

    if (_imageRotationIsolateSendPort != null) {
      try {
        print("****** ObjectDetectionView: Sending 'shutdown' to RotationIsolate.");
        _imageRotationIsolateSendPort!.send('shutdown');
      } catch (e) {
        print("****** ObjectDetectionView: Error sending 'shutdown' to RotationIsolate: $e. Isolate might have already exited.");
        _imageRotationIsolateSendPort = null;
      }
    } else {
      print("****** ObjectDetectionView: RotationIsolateSendPort is null. Cannot send shutdown.");
    }
  }

  void _forceKillRemainingIsolates() {
    print("****** ObjectDetectionView: _forceKillRemainingIsolates called.");
    if (_objectDetectionIsolate != null) {
      print("****** ObjectDetectionView: Force-killing DetectionIsolate.");
      _objectDetectionIsolate!.kill(priority: Isolate.immediate);
      _objectDetectionIsolate = null;
    }
    _objectDetectionIsolateSendPort = null; // SendPort도 확실히 정리

    if (_imageRotationIsolate != null) {
      print("****** ObjectDetectionView: Force-killing RotationIsolate.");
      _imageRotationIsolate!.kill(priority: Isolate.immediate);
      _imageRotationIsolate = null;
    }
    _imageRotationIsolateSendPort = null; // SendPort도 확실히 정리
    print("****** ObjectDetectionView: _forceKillRemainingIsolates completed.");
  }

  Future<bool> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn isolates.");
      return false;
    }

    try {
      _objectDetectionReceivePort = ReceivePort();
      _objectDetectionIsolate = await Isolate.spawn<IsolateDataHolder>(
          detectObjectsIsolateEntry,
          IsolateDataHolder(_objectDetectionReceivePort.sendPort, rootIsolateToken),
          onError: _objectDetectionReceivePort.sendPort,
          onExit: _objectDetectionReceivePort.sendPort,
          debugName: "ObjectDetectionIsolate_View");
      _objectDetectionSubscription = _objectDetectionReceivePort.listen(_handleDetectionResult,
        onError: (error, stackTrace) {
          print("****** ObjectDetectionView: Error in _objectDetectionReceivePort.listen: $error\n$stackTrace");
        },
        onDone: () {
          print("****** ObjectDetectionView: _objectDetectionReceivePort is done.");
        },
        cancelOnError: false // 오류 발생 시에도 스트림을 유지하여 ack 메시지 등을 받을 수 있도록 함
      );
      print("****** ObjectDetectionView: ObjectDetectionIsolate spawned.");

      _imageRotationReceivePort = ReceivePort();
      _imageRotationIsolate = await Isolate.spawn(
          getImageRotationIsolateEntry, _imageRotationReceivePort.sendPort,
          onError: _imageRotationReceivePort.sendPort,
          onExit: _imageRotationReceivePort.sendPort,
          debugName: "ImageRotationIsolate_View");
      _imageRotationSubscription = _imageRotationReceivePort.listen(_handleRotationResult,
        onError: (error, stackTrace) {
          print("****** ObjectDetectionView: Error in _imageRotationReceivePort.listen: $error\n$stackTrace");
        },
        onDone: () {
          print("****** ObjectDetectionView: _imageRotationReceivePort is done.");
        },
        cancelOnError: false
      );
      print("****** ObjectDetectionView: ImageRotationIsolate spawned.");
      return true;
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Failed to spawn isolates: $e\n$stacktrace");
      if (mounted && !_isDisposed) { // initState에서 setState 호출 시 mounted 확인
         setState(() {
            _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
         });
      } else if (!_isDisposed) { // initState 외부에서 _initializationErrorMsg 설정 시
         _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
      }
      return false;
    }
  }

  void _handleDetectionResult(dynamic message) {
    // 종료 신호 확인 및 처리 (가장 먼저)
    if (message == 'isolate_shutdown_ack_detection') {
        print("****** ObjectDetectionView: Detection isolate acknowledged shutdown. Nullifying isolate reference.");
        // Isolate가 자체적으로 종료했으므로, 여기서 kill을 호출할 필요는 없지만,
        // 만약을 위해 _forceKillRemainingIsolates에서 처리될 수 있도록 참조만 null로 설정
        _objectDetectionIsolate = null; 
        _objectDetectionIsolateSendPort = null;
        return;
    }

    // 위젯이 dispose되었거나, 종료 중이거나, 아직 mount되지 않은 경우 메시지 처리 중단 (SendPort 초기 설정 제외)
    if ((_isDisposed || _isShuttingDownIsolates || !mounted) && message is! SendPort) {
        print("****** ObjectDetectionView (_handleDetectionResult): View disposed/shutting_down/unmounted. Ignoring message: ${message.runtimeType}");
        return;
    }
    
    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
      return; // SendPort 설정 후 바로 다음 메시지 처리로 넘어가지 않도록 return
    }
    
    // 실제 데이터 처리 로직
    if (message is List<DetectedObject>) {
      // ... (기존 객체 처리 로직과 동일)
      List<DetectedObjectInfo> newProcessedObjects = [];
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
        newProcessedObjects.add(DetectedObjectInfo(
          object: largestMlKitObject,
          sizeCategory: sizeCategory,
          boundingBox: displayRect,
          label: mainLabel,
        ));
      }

      _isWaitingForDetection = false;
      if (mounted && !_isDisposed && !_isShuttingDownIsolates) { // setState 호출 조건 강화
        setState(() {
          _processedObjects = newProcessedObjects;
        });
      }
      if (!_isShuttingDownIsolates) { // 종료 중이 아닐 때만 콜백 호출
          widget.onObjectsDetected?.call(newProcessedObjects);
      }


      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List && message.length == 2 && message[0] is String && message[0].toString().contains('Error')) {
      print('****** ObjectDetectionView: Detection Isolate Error: ${message[1]}');
      if (mounted && !_isDisposed && !_isShuttingDownIsolates) setState(() => _processedObjects = []);
      if (!_isShuttingDownIsolates) widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! List<DetectedObject>)) {
      print('****** ObjectDetectionView: Detection Isolate exited or sent empty/null message ($message).');
      // Isolate가 예기치 않게 종료된 경우일 수 있음
      if (mounted && !_isDisposed && !_isShuttingDownIsolates) setState(() => _processedObjects = []);
      if (!_isShuttingDownIsolates) widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message is SendPort) {
        // 이미 위에서 처리됨. 여기서는 무시.
    } else {
      print('****** ObjectDetectionView: Unexpected message from Detection Isolate: ${message.runtimeType} - $message');
      if (mounted && !_isDisposed && !_isShuttingDownIsolates) setState(() => _processedObjects = []);
      if (!_isShuttingDownIsolates) widget.onObjectsDetected?.call([]);
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
    // ... (이전과 동일한 로직)
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
        l = mlKitBoundingBox.left * scaleX; t = mlKitBoundingBox.top * scaleY;
        r = mlKitBoundingBox.right * scaleX; b = mlKitBoundingBox.bottom * scaleY;
        break;
      case InputImageRotation.rotation90deg:
        l = mlKitBoundingBox.top * scaleX; t = (mlImageHeight - mlKitBoundingBox.right) * scaleY;
        r = mlKitBoundingBox.bottom * scaleX; b = (mlImageHeight - mlKitBoundingBox.left) * scaleY;
        break;
      case InputImageRotation.rotation180deg:
        l = (mlImageWidth - mlKitBoundingBox.right) * scaleX; t = (mlImageHeight - mlKitBoundingBox.bottom) * scaleY;
        r = (mlImageWidth - mlKitBoundingBox.left) * scaleX; b = (mlImageHeight - mlKitBoundingBox.top) * scaleY;
        break;
      case InputImageRotation.rotation270deg:
        l = (mlImageWidth - mlKitBoundingBox.bottom) * scaleX; t = mlKitBoundingBox.left * scaleY;
        r = (mlImageWidth - mlKitBoundingBox.top) * scaleX; b = mlKitBoundingBox.right * scaleY;
        break;
    }
    if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
       if (imageRotation == InputImageRotation.rotation0deg || imageRotation == InputImageRotation.rotation180deg) {
         final double tempL = l; l = cameraViewRect.width - r; r = cameraViewRect.width - tempL;
       }
    }
    Rect displayRect = Rect.fromLTRB(
        cameraViewRect.left + l, cameraViewRect.top + t,
        cameraViewRect.left + r, cameraViewRect.top + b);
    return Rect.fromLTRB(
      displayRect.left.clamp(cameraViewRect.left, cameraViewRect.right),
      displayRect.top.clamp(cameraViewRect.top, cameraViewRect.bottom),
      displayRect.right.clamp(cameraViewRect.left, cameraViewRect.right),
      displayRect.bottom.clamp(cameraViewRect.top, cameraViewRect.bottom),
    );
  }

  void _handleRotationResult(dynamic message) {
    if (message == 'isolate_shutdown_ack_rotation') {
        print("****** ObjectDetectionView: Rotation isolate acknowledged shutdown. Nullifying isolate reference.");
        _imageRotationIsolate = null;
        _imageRotationIsolateSendPort = null;
        return;
    }

    if ((_isDisposed || _isShuttingDownIsolates || !mounted) && message is! SendPort) {
        print("****** ObjectDetectionView (_handleRotationResult): View disposed/shutting_down/unmounted. Ignoring message: ${message.runtimeType}");
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
        if (!_isDisposed && !_isShuttingDownIsolates && _objectDetectionIsolateSendPort != null) { // SendPort null 체크 추가
             _objectDetectionIsolateSendPort!.send(payload);
        } else {
          print("****** ObjectDetectionView: Not sending to detection isolate (disposed, shutting down, or no sendPort)");
          // 전송하지 못했으므로 _isWaitingForDetection을 false로 되돌리고 _isBusy도 해제 시도
          _isWaitingForDetection = false;
          if (!_isWaitingForRotation && _isBusy) _isBusy = false;
        }
        _pendingImageDataBytes = null; // 전송 시도 후에는 항상 null로 설정
      } else {
        // _pendingImageDataBytes가 null이거나, detection isolate send port가 없거나, message가 null인 경우
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
    } else if (message is SendPort) {
        // 이미 위에서 처리됨.
    }
     else {
      print('****** ObjectDetectionView: Unexpected message from Rotation Isolate: ${message.runtimeType} - $message');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    print("****** ObjectDetectionView: _initializeCamera called for ${cameraDescription.name}. _isDisposed: $_isDisposed");
    if (_isDisposed) return;

    // 이전 카메라 컨트롤러 정리
    if (_cameraController != null) {
      print("****** ObjectDetectionView: Disposing previous camera controller.");
      await _stopCameraStream(); // 스트림 먼저 중지
      try {
        await _cameraController!.dispose();
        print("****** ObjectDetectionView: Previous CameraController disposed successfully.");
      } catch (e) {
        print("****** ObjectDetectionView: Error disposing previous CameraController: $e");
      }
      _cameraController = null;
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _isCameraInitialized = false;
        _initializationErrorMsg = null;
      });
    } else if (!_isDisposed) { // mounted 안됐어도 초기화는 시도 (예: initState에서)
        _isCameraInitialized = false;
        _initializationErrorMsg = null;
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
      await _startCameraStream(); // 초기화 성공 후 스트림 시작
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
    print("****** ObjectDetectionView: _startCameraStream called. _isDisposed: $_isDisposed, Controller null: ${_cameraController == null}");
    if (_isDisposed || _cameraController == null || !_cameraController!.value.isInitialized || _cameraController!.value.isStreamingImages) {
      print("****** ObjectDetectionView: Conditions not met to start stream. Initialized: ${_cameraController?.value.isInitialized}, Streaming: ${_cameraController?.value.isStreamingImages}");
      return;
    }
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
    print("****** ObjectDetectionView: _stopCameraStream called. Controller: ${_cameraController != null}, Initialized: ${_cameraController?.value.isInitialized}, Streaming: ${_cameraController?.value.isStreamingImages}");
    if (_cameraController == null || !_cameraController!.value.isInitialized || !_cameraController!.value.isStreamingImages) {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
      print("****** ObjectDetectionView: _stopCameraStream: Not streaming or controller not ready. Flags reset.");
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      print("****** ObjectDetectionView: Camera stream stopped successfully in _stopCameraStream for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Error stopping image stream in _stopCameraStream: $e\n$stacktrace');
    } finally {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
      print("****** ObjectDetectionView: _stopCameraStream: Flags reset in finally block.");
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isDisposed || _isShuttingDownIsolates || !mounted || _isBusy || _imageRotationIsolateSendPort == null) {
      return;
    }
    _isBusy = true; // 여기서 busy 설정
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

      if (!_isDisposed && !_isShuttingDownIsolates && _imageRotationIsolateSendPort != null) { 
         _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
         print("****** ObjectDetectionView: Not sending to rotation isolate (disposed, shutting down, or no sendPort)");
         _pendingImageDataBytes = null; 
         _isWaitingForRotation = false;
         _isBusy = false; // busy 해제
      }
    } catch (e, stacktrace) {
      print("****** ObjectDetectionView: Error processing image: $e\n$stacktrace");
      _pendingImageDataBytes = null;
      _isWaitingForRotation = false;
      _isBusy = false; // 오류 발생 시 busy 해제
    }
  }

  void _switchCamera() {
    if (_isDisposed || widget.cameras.length < 2 || _isBusy || _isShuttingDownIsolates) return;
    print("****** ObjectDetectionView: Switching camera...");
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    
    // 비동기 작업으로 전환하여 현재 빌드 사이클과 분리
    Future.microtask(() async {
        print("****** ObjectDetectionView: Microtask for _switchCamera started.");
        await _stopCameraStream(); // 현재 스트림과 busy 상태 정리
        if (!_isDisposed && mounted) { // dispose나 unmount 안됐는지 확인
            await _initializeCamera(widget.cameras[newIndex]); 
        }
        print("****** ObjectDetectionView: Microtask for _switchCamera finished.");
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
