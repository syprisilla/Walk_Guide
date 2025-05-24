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
import 'camera_screen.dart' show IsolateDataHolder; // IsolateDataHolder 정의를 가져옴

// 객체 크기 카테고리 및 정보 클래스 정의
enum ObjectSizeCategory { small, medium, large, unknown }

class DetectedObjectInfo {
  final DetectedObject object;
  final ObjectSizeCategory sizeCategory;
  final Rect boundingBox; // 화면 좌표계의 바운딩 박스 (Painter에서 사용된 displayRect와 유사)
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
  final Function(List<DetectedObjectInfo> objectsInfo)? onObjectsDetected; // 콜백 타입 변경
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
  List<DetectedObjectInfo> _processedObjects = []; // 화면 표시 및 콜백용 객체 정보
  InputImageRotation? _imageRotation;
  late ObjectDetector _objectDetector;
  Size? _lastImageSize; // 카메라 이미지 원본 크기
  Size? _screenSize;    // 현재 화면(캔버스) 크기

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
    _isDisposed = true;

    Future.microtask(() async {
      await _stopCameraStream();

      await _objectDetectionSubscription?.cancel();
      _objectDetectionSubscription = null;
      await _imageRotationSubscription?.cancel();
      _imageRotationSubscription = null;
      print("****** ObjectDetectionView: Subscriptions cancelled.");

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

      _killIsolates();

      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed.");
      } catch (e, stacktrace) {
        print('****** ObjectDetectionView: Error disposing CameraController: $e\n$stacktrace');
      }
      _cameraController = null;

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
          IsolateDataHolder(_objectDetectionReceivePort.sendPort, rootIsolateToken), // 세 번째 인자 제거
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
    if (_objectDetectionIsolateSendPort != null && !_isDisposed) {
        _objectDetectionIsolateSendPort!.send('shutdown');
        print("****** ObjectDetectionView: Sent 'shutdown' to DetectionIsolate.");
    } else {
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      _objectDetectionIsolate = null;
      print("****** ObjectDetectionView: DetectionIsolate killed (no SendPort or already disposed).");
    }
    _objectDetectionIsolateSendPort = null;

    if (_imageRotationIsolateSendPort != null && !_isDisposed) {
        _imageRotationIsolateSendPort!.send('shutdown');
        print("****** ObjectDetectionView: Sent 'shutdown' to RotationIsolate.");
    } else {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      _imageRotationIsolate = null;
      print("****** ObjectDetectionView: RotationIsolate killed (no SendPort or already disposed).");
    }
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_detection') {
        print("****** ObjectDetectionView: Detection isolate acknowledged shutdown. Killing now.");
        _objectDetectionIsolate?.kill(priority: Isolate.immediate);
        _objectDetectionIsolate = null;
        return;
    }

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print("****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
    } else if (message is List<DetectedObject>) {
      List<DetectedObjectInfo> newProcessedObjects = [];

      if (message.isNotEmpty && _lastImageSize != null && _screenSize != null && _imageRotation != null && _cameraController != null) {
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
        if (_screenSize!.width > 0 && _screenSize!.height > 0) { // 화면 크기가 유효할 때만 계산
            final double screenArea = _screenSize!.width * _screenSize!.height;
            final double objectArea = displayRect.width * displayRect.height;
            if (screenArea > 0) {
                final double areaRatio = objectArea / screenArea;
                // 크기 임계값은 실제 테스트를 통해 조정 필요
                if (areaRatio > 0.20) { // 예: 화면의 20% 이상
                    sizeCategory = ObjectSizeCategory.large;
                } else if (areaRatio > 0.05) { // 예: 화면의 5% 이상
                    sizeCategory = ObjectSizeCategory.medium;
                } else if (areaRatio > 0.005) { // 예: 화면의 0.5% 이상 (더 작은 값으로 조정 가능)
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
      print('****** ObjectDetectionView: Detection Isolate exited or sent empty/null message ($message).');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
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
    required Size originalImageSize, // 카메라에서 받은 이미지의 원본 크기
    required Size canvasSize,        // 화면에 그려지는 캔버스의 크기 (LayoutBuilder의 constraints.biggest)
    required InputImageRotation imageRotation, // 이미지 회전 정보
    required CameraLensDirection cameraLensDirection, // 카메라 렌즈 방향
    required double cameraPreviewAspectRatio,    // 카메라 프리뷰의 종횡비
  }) {
    if (originalImageSize.isEmpty || canvasSize.isEmpty || cameraPreviewAspectRatio <= 0) {
      return Rect.zero;
    }

    // 1. CameraPreview 위젯이 화면(canvasSize) 내에서 차지하는 실제 영역(cameraViewRect) 계산
    //    (ObjectPainter의 cameraViewRect 계산 로직과 동일하게)
    Rect cameraViewRect;
    final double screenAspectRatio = canvasSize.width / canvasSize.height;

    if (screenAspectRatio > cameraPreviewAspectRatio) { // 화면이 프리뷰보다 가로로 넓은 경우 (프리뷰가 세로로 꽉 참)
      final double fittedHeight = canvasSize.height;
      final double fittedWidth = fittedHeight * cameraPreviewAspectRatio;
      final double offsetX = (canvasSize.width - fittedWidth) / 2;
      cameraViewRect = Rect.fromLTWH(offsetX, 0, fittedWidth, fittedHeight);
    } else { // 화면이 프리뷰보다 세로로 길거나 같은 비율인 경우 (프리뷰가 가로로 꽉 참)
      final double fittedWidth = canvasSize.width;
      final double fittedHeight = fittedWidth / cameraPreviewAspectRatio;
      final double offsetY = (canvasSize.height - fittedHeight) / 2;
      cameraViewRect = Rect.fromLTWH(0, offsetY, fittedWidth, fittedHeight);
    }

    // 2. ML Kit 바운딩 박스를 cameraViewRect에 맞게 스케일링 및 변환
    final bool isImageRotatedSideways =
        imageRotation == InputImageRotation.rotation90deg ||
            imageRotation == InputImageRotation.rotation270deg;

    // ML Kit이 처리한 이미지의 크기 (회전 고려)
    final double mlImageWidth = isImageRotatedSideways ? originalImageSize.height : originalImageSize.width;
    final double mlImageHeight = isImageRotatedSideways ? originalImageSize.width : originalImageSize.height;

    if (mlImageWidth == 0 || mlImageHeight == 0) return Rect.zero;

    // 스케일 팩터: ML Kit 이미지 크기 -> cameraViewRect 크기
    final double scaleX = cameraViewRect.width / mlImageWidth;
    final double scaleY = cameraViewRect.height / mlImageHeight;

    double l, t, r, b; // cameraViewRect 내에서의 상대적 좌표

    switch (imageRotation) {
      case InputImageRotation.rotation0deg:
        l = mlKitBoundingBox.left * scaleX;
        t = mlKitBoundingBox.top * scaleY;
        r = mlKitBoundingBox.right * scaleX;
        b = mlKitBoundingBox.bottom * scaleY;
        break;
      case InputImageRotation.rotation90deg: // 이미지 시계방향 90도 회전됨 (ML Kit은 이 회전된 이미지를 처리)
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
      case InputImageRotation.rotation270deg: // 이미지 시계방향 270도 (반시계 90도) 회전됨
        l = (mlImageWidth - mlKitBoundingBox.bottom) * scaleX;
        t = mlKitBoundingBox.left * scaleY;
        r = (mlImageWidth - mlKitBoundingBox.top) * scaleX;
        b = mlKitBoundingBox.right * scaleY;
        break;
    }
    
    // Android 전면 카메라 미러링 처리 (ObjectPainter와 동일하게)
    if (cameraLensDirection == CameraLensDirection.front && Platform.isAndroid) {
       if (imageRotation == InputImageRotation.rotation0deg || imageRotation == InputImageRotation.rotation180deg) {
         final double tempL = l;
         l = cameraViewRect.width - r; // cameraViewRect.width 기준으로 미러링
         r = cameraViewRect.width - tempL;
       }
       // 90, 270도의 경우, Android 전면 카메라는 이미 미러링된 이미지를 제공하거나,
       // _calculateRotation에서 이미 최종 방향이 결정되었을 수 있습니다.
       // ObjectPainter의 로직을 정확히 따르는 것이 중요합니다.
       // 만약 ObjectPainter에서 90/270도에 대해 추가적인 미러링을 한다면 여기서도 반영해야 합니다.
       // 현재 ObjectPainter는 90/270도에 대한 특별한 미러링 로직은 없어 보입니다.
    }

    // 최종 화면(canvas) 좌표로 변환: cameraViewRect의 offset을 더함
    Rect displayRect = Rect.fromLTRB(
        cameraViewRect.left + l,
        cameraViewRect.top + t,
        cameraViewRect.left + r,
        cameraViewRect.top + b);

    // 클리핑: 계산된 displayRect가 cameraViewRect를 벗어나지 않도록 (ObjectPainter와 동일)
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
        // _lastImageSize는 _processCameraImage에서 설정됨
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
      if(_isBusy && !_isDisposed) {
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

      _lastImageSize = Size(image.width.toDouble(), image.height.toDouble()); // 카메라 이미지 원본 크기 저장

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
         print("****** ObjectDetectionView: Not sending to rotation isolate (disposed or no sendPort)");
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
        _screenSize = constraints.biggest; // 화면 크기 업데이트
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
            if (_processedObjects.isNotEmpty && _lastImageSize != null && _imageRotation != null && _screenSize != null) // _screenSize null 체크 추가
              CustomPaint(
                size: parentSize,
                painter: ObjectPainter(
                  objects: _processedObjects.map((info) => info.object).toList(), // Painter는 DetectedObject 리스트를 받음
                  imageSize: _lastImageSize!,
                  screenSize: _screenSize!, // screenSize 전달
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