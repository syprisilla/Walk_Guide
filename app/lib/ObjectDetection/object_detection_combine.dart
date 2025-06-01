import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

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

class BoundingBoxUtils {
  static Rect scaleAndTranslateRect({
    required Rect boundingBox,
    required Size imageSize,
    required Size canvasSize,
    required InputImageRotation rotation,
    required CameraLensDirection cameraLensDirection,
  }) {
    final double imageWidth = imageSize.width;
    final double imageHeight = imageSize.height;
    final double canvasWidth = canvasSize.width;
    final double canvasHeight = canvasSize.height;

    final double scaleX, scaleY;
    if (_isRotationSideways(rotation)) {
      scaleX = canvasWidth / imageHeight;
      scaleY = canvasHeight / imageWidth;
    } else {
      scaleX = canvasWidth / imageWidth;
      scaleY = canvasHeight / imageHeight;
    }

    // 좌표 변환
    double l, t, r, b;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        l = boundingBox.top * scaleX;
        t = (imageWidth - boundingBox.right) * scaleY;
        r = boundingBox.bottom * scaleX;
        b = (imageWidth - boundingBox.left) * scaleY;
        break;
      case InputImageRotation.rotation180deg:
        l = (imageWidth - boundingBox.right) * scaleX;
        t = (imageHeight - boundingBox.bottom) * scaleY;
        r = (imageWidth - boundingBox.left) * scaleX;
        b = (imageHeight - boundingBox.top) * scaleY;
        break;
      case InputImageRotation.rotation270deg:
        l = (imageHeight - boundingBox.bottom) * scaleX;
        t = boundingBox.left * scaleY;
        r = (imageHeight - boundingBox.top) * scaleX;
        b = boundingBox.right * scaleY;
        break;
      case InputImageRotation.rotation0deg:
      default:
        l = boundingBox.left * scaleX;
        t = boundingBox.top * scaleY;
        r = boundingBox.right * scaleX;
        b = boundingBox.bottom * scaleY;
        break;
    }

    // 미러링
    if (cameraLensDirection == CameraLensDirection.front &&
        Platform.isAndroid) {
      double tempL = l;
      l = canvasWidth - r;
      r = canvasWidth - tempL;
    }

    // 범위 제한 및 보정
    l = l.clamp(0.0, canvasWidth);
    t = t.clamp(0.0, canvasHeight);
    r = r.clamp(0.0, canvasWidth);
    b = b.clamp(0.0, canvasHeight);
    if (l > r) {
      double temp = l;
      l = r;
      r = temp;
    }
    if (t > b) {
      double temp = t;
      t = b;
      b = temp;
    }

    return Rect.fromLTRB(l, t, r, b);
  }

  // 바운딩 박스 그리기 함수
  static void paintBoundingBox(Canvas canvas, Rect rect) {
    final Paint paintRect = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    if (rect.width > 0 && rect.height > 0) {
      canvas.drawRect(rect, paintRect);
    }
  }

  // 내부 헬퍼 함수
  static bool _isRotationSideways(InputImageRotation rotation) {
    return rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
  }
}

// --- From name_tag_painter.dart ---
class NameTagUtils {
  // 네임태그 그리기 함수
  static void paintNameTag({
    required Canvas canvas,
    required Label label,
    required Rect boundingBoxRect, // 기준 박스 위치
    required Size canvasSize,
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text:
            ' ${label.text} (${(label.confidence * 100).toStringAsFixed(0)}%) ',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.0,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(minWidth: 0, maxWidth: canvasSize.width);

    // 텍스트 위치 계산 및 조정
    double textY = boundingBoxRect.top - textPainter.height;
    if (textY < 0) {
      textY = boundingBoxRect.top + 2;
      if (textY + textPainter.height > canvasSize.height) {
        textY = boundingBoxRect.bottom - textPainter.height - 2;
      }
    }
    final Offset textOffset = Offset(boundingBoxRect.left,
        textY.clamp(0.0, canvasSize.height - textPainter.height));

    // 텍스트 그리기
    textPainter.paint(canvas, textOffset);
  }
}

// --- From camera_screen.dart (IsolateDataHolder) ---
class IsolateDataHolder {
  final SendPort mainSendPort;
  final RootIsolateToken? rootIsolateToken;

  IsolateDataHolder(this.mainSendPort, this.rootIsolateToken);
}

// --- From mlkit_object_detection.dart ---
ObjectDetector initializeObjectDetector() {
  print("Logic: Initializing ObjectDetector (ML Kit)...");
  final options = ObjectDetectorOptions(
    mode: DetectionMode.stream,
    classifyObjects: true,
    multipleObjects: true,
  );
  return ObjectDetector(options: options);
}

void getImageRotationIsolateEntry(SendPort mainSendPort) {
  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);
  bool isShuttingDown = false;

  isolateReceivePort.listen((dynamic message) {
    if (isShuttingDown) return;

    if (message == 'shutdown') {
      isShuttingDown = true;
      print("****** ImageRotationIsolate: Shutdown signal received.");
      isolateReceivePort.close();
      try {
        mainSendPort.send('isolate_shutdown_ack_rotation');
      } catch (e) {
        print("****** ImageRotationIsolate: Error sending shutdown ack: $e");
      }
      return;
    }
    try {
      if (message is Map<String, dynamic>) {
        final int sensorOrientation = message['sensorOrientation'];
        final int deviceOrientationIndex = message['deviceOrientationIndex'];
        final DeviceOrientation deviceOrientation =
            DeviceOrientation.values[deviceOrientationIndex];

        final InputImageRotation rotation =
            _calculateRotation(sensorOrientation, deviceOrientation);
        if (!isShuttingDown) mainSendPort.send(rotation);
      } else {
        throw Exception(
            "Invalid message type for rotation isolate: ${message.runtimeType}");
      }
    } catch (e, stacktrace) {
      print('****** Rotation Isolate Error: $e\n$stacktrace');
      if (!isShuttingDown)
        mainSendPort.send(['Error from RotationIsolate', e.toString()]);
    }
  });
}

InputImageRotation _calculateRotation(
    int sensorOrientation, DeviceOrientation deviceOrientation) {
  if (Platform.isIOS) {
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        return InputImageRotation.rotation0deg;
      case DeviceOrientation.landscapeLeft:
        return InputImageRotation.rotation270deg;
      case DeviceOrientation.portraitDown:
        return InputImageRotation.rotation180deg;
      case DeviceOrientation.landscapeRight:
        return InputImageRotation.rotation90deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  int rotationCompensation = 0;
  switch (deviceOrientation) {
    case DeviceOrientation.portraitUp:
      rotationCompensation = 0;
      break;
    case DeviceOrientation.landscapeLeft:
      rotationCompensation = 90;
      break;
    case DeviceOrientation.portraitDown:
      rotationCompensation = 180;
      break;
    case DeviceOrientation.landscapeRight:
      rotationCompensation = 270;
      break;
  }
  int resultRotationDegrees =
      (sensorOrientation - rotationCompensation + 360) % 360;

  switch (resultRotationDegrees) {
    case 0:
      return InputImageRotation.rotation0deg;
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      print(
          '****** Unknown rotation degrees: $resultRotationDegrees. Defaulting to 0deg.');
      return InputImageRotation.rotation0deg;
  }
}

void detectObjectsIsolateEntry(IsolateDataHolder isolateDataHolder) {
  final SendPort mainSendPort = isolateDataHolder.mainSendPort;
  final RootIsolateToken? rootIsolateToken = isolateDataHolder.rootIsolateToken;

  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    print("DetectionIsolate: BackgroundIsolateBinaryMessenger initialized.");
  } else {
    print(
        "****** Detection Isolate: RootIsolateToken is null. ML Kit might fail.");
  }

  final ObjectDetector objectDetector = initializeObjectDetector();
  print("DetectionIsolate: Isolate-specific ObjectDetector initialized.");
  bool isShuttingDown = false;

  isolateReceivePort.listen((dynamic message) async {
    if (isShuttingDown) return;

    if (message == 'shutdown') {
      isShuttingDown = true;
      print("****** DetectionIsolate: Shutdown signal received.");
      try {
        await objectDetector.close();
        print(
            "****** DetectionIsolate: Isolate-specific ObjectDetector closed.");
      } catch (e, stacktrace) {
        print(
            "****** DetectionIsolate: Error closing ObjectDetector: $e\n$stacktrace");
      }
      isolateReceivePort.close();
      try {
        mainSendPort.send('isolate_shutdown_ack_detection');
      } catch (e) {
        print("****** DetectionIsolate: Error sending shutdown ack: $e");
      }
      return;
    }

    if (message is Map<String, dynamic>) {
      try {
        final Uint8List bytes = message['bytes'];
        final int width = message['width'];
        final int height = message['height'];
        final InputImageRotation rotation = message['rotation'];
        final int formatRaw = message['formatRaw'];
        final int bytesPerRowData = message['bytesPerRow'];

        final InputImageFormat imageFormat =
            InputImageFormatValue.fromRawValue(formatRaw) ??
                InputImageFormat.nv21;

        final InputImageMetadata metadata = InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: imageFormat,
          bytesPerRow: bytesPerRowData,
        );

        final InputImage inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );

        final List<DetectedObject> objects =
            await objectDetector.processImage(inputImage);
        if (!isShuttingDown) mainSendPort.send(objects);
      } catch (e, stacktrace) {
        print('****** Detection Isolate processImage Error: $e\n$stacktrace');
        if (!isShuttingDown)
          mainSendPort.send(['Error from DetectionIsolate', e.toString()]);
      }
    } else {
      print(
          '****** Detection Isolate received invalid message type: ${message.runtimeType}');
      if (!isShuttingDown)
        mainSendPort.send([
          'Error from DetectionIsolate',
          'Invalid message type: ${message.runtimeType}'
        ]);
    }
  });
}

// --- From object_painter.dart ---
class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size screenSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final double cameraPreviewAspectRatio;
  final bool showNameTags; // NameTag 표시 여부 플래그

  ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
    required this.cameraPreviewAspectRatio,
    this.showNameTags = false, // 기본값 false (NameTag 안 그림)
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty || size.isEmpty || cameraPreviewAspectRatio <= 0) {
      return;
    }

    final Paint paintRect = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.lightGreenAccent;

    Rect cameraViewRect;
    final double screenAspectRatio = size.width / size.height;

    if (screenAspectRatio > cameraPreviewAspectRatio) {
      final double fittedHeight = size.height;
      final double fittedWidth = fittedHeight * cameraPreviewAspectRatio;
      final double offsetX = (size.width - fittedWidth) / 2;
      cameraViewRect = Rect.fromLTWH(offsetX, 0, fittedWidth, fittedHeight);
    } else {
      final double fittedWidth = size.width;
      final double fittedHeight = fittedWidth / cameraPreviewAspectRatio;
      final double offsetY = (size.height - fittedHeight) / 2;
      cameraViewRect = Rect.fromLTWH(0, offsetY, fittedWidth, fittedHeight);
    }

    for (final DetectedObject detectedObject in objects) {
      final Rect boundingBox = detectedObject.boundingBox;

      final bool isImageRotatedSideways =
          rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg;

      final double mlImageWidth =
          isImageRotatedSideways ? imageSize.height : imageSize.width;
      final double mlImageHeight =
          isImageRotatedSideways ? imageSize.width : imageSize.height;

      if (mlImageWidth == 0 || mlImageHeight == 0) continue;

      final double scaleX = cameraViewRect.width / mlImageWidth;
      final double scaleY = cameraViewRect.height / mlImageHeight;

      Rect displayRect;
      double l, t, r, b;

      switch (rotation) {
        case InputImageRotation.rotation0deg:
          l = boundingBox.left * scaleX;
          t = boundingBox.top * scaleY;
          r = boundingBox.right * scaleX;
          b = boundingBox.bottom * scaleY;
          break;
        case InputImageRotation.rotation90deg:
          l = boundingBox.top * scaleX;
          t = (mlImageHeight - boundingBox.right) * scaleY;
          r = boundingBox.bottom * scaleX;
          b = (mlImageHeight - boundingBox.left) * scaleY;
          break;
        case InputImageRotation.rotation180deg:
          l = (mlImageWidth - boundingBox.right) * scaleX;
          t = (mlImageHeight - boundingBox.bottom) * scaleY;
          r = (mlImageWidth - boundingBox.left) * scaleX;
          b = (mlImageHeight - boundingBox.top) * scaleY;
          break;
        case InputImageRotation.rotation270deg:
          l = (mlImageWidth - boundingBox.bottom) * scaleX;
          t = boundingBox.left * scaleY;
          r = (mlImageWidth - boundingBox.top) * scaleX;
          b = boundingBox.right * scaleY;
          break;
      }

      if (cameraLensDirection == CameraLensDirection.front &&
          Platform.isAndroid) {
        if (rotation == InputImageRotation.rotation0deg ||
            rotation == InputImageRotation.rotation180deg) {
          final double tempL = l;
          l = cameraViewRect.width - r;
          r = cameraViewRect.width - tempL;
        }
      }

      displayRect = Rect.fromLTRB(
          cameraViewRect.left + l,
          cameraViewRect.top + t,
          cameraViewRect.left + r,
          cameraViewRect.top + b);

      displayRect = Rect.fromLTRB(
          displayRect.left.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.top.clamp(cameraViewRect.top, cameraViewRect.bottom),
          displayRect.right.clamp(cameraViewRect.left, cameraViewRect.right),
          displayRect.bottom.clamp(cameraViewRect.top, cameraViewRect.bottom));

      if (displayRect.width > 0 && displayRect.height > 0) {
        canvas.drawRect(displayRect, paintRect);

        // NameTag 표시 로직 (showNameTags 플래그가 true일 때만 실행)
        if (showNameTags && detectedObject.labels.isNotEmpty) {
          final Paint backgroundPaint = Paint()
            ..color = Colors.black.withOpacity(0.6);
          final label = detectedObject.labels.first;
          final TextSpan span = TextSpan(
            text:
                ' ${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0,
                fontWeight: FontWeight.bold),
          );
          final TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          );
          tp.layout();

          double textBgTop = displayRect.top - tp.height - 4;
          if (textBgTop < cameraViewRect.top) {
            textBgTop = displayRect.bottom + 2;
          }
          if (textBgTop + tp.height + 4 > cameraViewRect.bottom &&
              displayRect.top - tp.height - 4 >= cameraViewRect.top) {
            textBgTop = displayRect.top - tp.height - 4;
          } else if (textBgTop + tp.height + 4 > cameraViewRect.bottom) {
            textBgTop = cameraViewRect.bottom - tp.height - 4;
          }

          double textBgLeft = displayRect.left;
          if (textBgLeft + tp.width + 8 > cameraViewRect.right) {
            textBgLeft = cameraViewRect.right - tp.width - 8;
          }
          if (textBgLeft < cameraViewRect.left) {
            textBgLeft = cameraViewRect.left;
          }

          final Rect textBackgroundRect =
              Rect.fromLTWH(textBgLeft, textBgTop, tp.width + 8, tp.height + 4);

          canvas.drawRect(textBackgroundRect, backgroundPaint);
          tp.paint(canvas,
              Offset(textBackgroundRect.left + 4, textBackgroundRect.top + 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.cameraPreviewAspectRatio != cameraPreviewAspectRatio ||
        oldDelegate.showNameTags != showNameTags; // showNameTags 변경 시에도 다시 그리도록
  }
}

// --- From object_detection_view.dart (Main View Class) ---
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
      print(
          "****** ObjectDetectionView initState (_spawnIsolates catchError): $e\n$stacktrace");
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
        print(
            "****** ObjectDetectionView: Object detection receive port closed.");
      } catch (e) {
        print(
            "****** ObjectDetectionView: Error closing object detection receive port: $e");
      }
      try {
        _imageRotationReceivePort.close();
        print(
            "****** ObjectDetectionView: Image rotation receive port closed.");
      } catch (e) {
        print(
            "****** ObjectDetectionView: Error closing image rotation receive port: $e");
      }

      _killIsolates();

      try {
        await _cameraController?.dispose();
        print("****** ObjectDetectionView: CameraController disposed.");
      } catch (e, stacktrace) {
        print(
            '****** ObjectDetectionView: Error disposing CameraController: $e\n$stacktrace');
      }
      _cameraController = null;

      try {
        await _objectDetector.close();
        print("****** ObjectDetectionView: Main ObjectDetector closed.");
      } catch (e, stacktrace) {
        print(
            '****** ObjectDetectionView: Error closing main ObjectDetector: $e\n$stacktrace');
      }
    });

    super.dispose();
    print("****** ObjectDetectionView: Dispose completed for super.");
  }

  Future<bool> _spawnIsolates() async {
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print(
          "****** ObjectDetectionView: RootIsolateToken is null. Cannot spawn isolates.");
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
      print("****** ObjectDetectionView: ObjectDetectionIsolate spawned.");

      _imageRotationReceivePort = ReceivePort();
      _imageRotationIsolate = await Isolate.spawn(
          getImageRotationIsolateEntry, _imageRotationReceivePort.sendPort,
          onError: _imageRotationReceivePort.sendPort,
          onExit: _imageRotationReceivePort.sendPort,
          debugName: "ImageRotationIsolate_View");
      _imageRotationSubscription =
          _imageRotationReceivePort.listen(_handleRotationResult);
      print("****** ObjectDetectionView: ImageRotationIsolate spawned.");
      return true;
    } catch (e, stacktrace) {
      print(
          "****** ObjectDetectionView: Failed to spawn isolates: $e\n$stacktrace");
      _initializationErrorMsg = "백그라운드 작업 생성 실패: $e";
      if (mounted && !_isDisposed) setState(() {});
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
      print(
          "****** ObjectDetectionView: DetectionIsolate killed (no SendPort or already disposed).");
    }
    _objectDetectionIsolateSendPort = null;

    if (_imageRotationIsolateSendPort != null && !_isDisposed) {
      _imageRotationIsolateSendPort!.send('shutdown');
      print("****** ObjectDetectionView: Sent 'shutdown' to RotationIsolate.");
    } else {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      _imageRotationIsolate = null;
      print(
          "****** ObjectDetectionView: RotationIsolate killed (no SendPort or already disposed).");
    }
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (_isDisposed || !mounted) return;

    if (message == 'isolate_shutdown_ack_detection') {
      print(
          "****** ObjectDetectionView: Detection isolate acknowledged shutdown. Killing now.");
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      _objectDetectionIsolate = null;
      return;
    }

    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
      print(
          "****** ObjectDetectionView: ObjectDetectionIsolate SendPort received.");
    } else if (message is List<DetectedObject>) {
      List<DetectedObjectInfo> newProcessedObjects = [];

      if (message.isNotEmpty &&
          _lastImageSize != null &&
          _screenSize != null &&
          _imageRotation != null &&
          _cameraController != null) {
        DetectedObject largestMlKitObject = message.reduce((curr, next) {
          final double areaCurr =
              curr.boundingBox.width * curr.boundingBox.height;
          final double areaNext =
              next.boundingBox.width * next.boundingBox.height;
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

        final String? mainLabel = largestMlKitObject.labels.isNotEmpty
            ? largestMlKitObject.labels.first.text
            : null;

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
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].toString().contains('Error')) {
      print(
          '****** ObjectDetectionView: Detection Isolate Error: ${message[1]}');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else if (message == null ||
        (message is List &&
            message.isEmpty &&
            message is! List<DetectedObject>)) {
      print(
          '****** ObjectDetectionView: Detection Isolate exited or sent empty/null message ($message).');
      if (mounted && !_isDisposed) setState(() => _processedObjects = []);
      widget.onObjectsDetected?.call([]);
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation && _isBusy) _isBusy = false;
    } else {
      print(
          '****** ObjectDetectionView: Unexpected message from Detection Isolate: ${message.runtimeType} - $message');
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
    if (originalImageSize.isEmpty ||
        canvasSize.isEmpty ||
        cameraPreviewAspectRatio <= 0) {
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

    final double mlImageWidth = isImageRotatedSideways
        ? originalImageSize.height
        : originalImageSize.width;
    final double mlImageHeight = isImageRotatedSideways
        ? originalImageSize.width
        : originalImageSize.height;

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

    if (cameraLensDirection == CameraLensDirection.front &&
        Platform.isAndroid) {
      if (imageRotation == InputImageRotation.rotation0deg ||
          imageRotation == InputImageRotation.rotation180deg) {
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
      print(
          "****** ObjectDetectionView: Rotation isolate acknowledged shutdown. Killing now.");
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      _imageRotationIsolate = null;
      return;
    }

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      _imageRotationIsolateSendPort = message;
      print(
          "****** ObjectDetectionView: ImageRotationIsolate SendPort received.");
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;
      _imageRotation = message;

      if (_pendingImageDataBytes != null &&
          _objectDetectionIsolateSendPort != null &&
          message != null) {
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
          print(
              "****** ObjectDetectionView: Not sending to detection isolate (disposed or no sendPort)");
        }
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
          '****** ObjectDetectionView: Rotation Isolate exited or sent empty/null message ($message).');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else {
      print(
          '****** ObjectDetectionView: Unexpected message from Rotation Isolate: ${message.runtimeType} - $message');
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
      print(
          "****** ObjectDetectionView: Old CameraController disposed before new init for ${cameraDescription.name}.");
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
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _cameraController!.initialize();
      print(
          "****** ObjectDetectionView: New CameraController initialized for ${cameraDescription.name}.");
      await _startCameraStream();
      if (mounted && !_isDisposed) {
        setState(() {
          _isCameraInitialized = true;
          _cameraIndex = widget.cameras.indexOf(cameraDescription);
        });
      }
    } catch (e, stacktrace) {
      print(
          '****** ObjectDetectionView: Camera init error for ${cameraDescription.name}: $e\n$stacktrace');
      if (mounted && !_isDisposed) {
        setState(() {
          _isCameraInitialized = false;
          _initializationErrorMsg =
              "카메라 시작에 실패했습니다.\n권한 확인 또는 앱 재시작 필요.\n오류: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
        });
      }
    }
  }

  Future<void> _startCameraStream() async {
    if (_isDisposed ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isStreamingImages) return;
    try {
      await _cameraController!.startImageStream(_processCameraImage);
      print(
          "****** ObjectDetectionView: Camera stream started for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print('****** ObjectDetectionView: Start stream error: $e\n$stacktrace');
      if (mounted && !_isDisposed) {
        setState(() {
          _initializationErrorMsg =
              "카메라 스트림 시작 실패: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}";
        });
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_cameraController!.value.isStreamingImages) {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      print(
          "****** ObjectDetectionView: Camera stream stopped in _stopCameraStream for ${_cameraController?.description.name}.");
    } catch (e, stacktrace) {
      print(
          '****** ObjectDetectionView: Stop stream error in _stopCameraStream: $e\n$stacktrace');
    } finally {
      _isBusy = false;
      _isWaitingForRotation = false;
      _isWaitingForDetection = false;
      _pendingImageDataBytes = null;
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isDisposed ||
        !mounted ||
        _isBusy ||
        _imageRotationIsolateSendPort == null) {
      if (_isBusy && !_isDisposed) {}
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

      _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

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
      if (!_isDisposed && _imageRotationIsolateSendPort != null) {
        _imageRotationIsolateSendPort!.send(rotationPayload);
      } else {
        print(
            "****** ObjectDetectionView: Not sending to rotation isolate (disposed or no sendPort)");
        _pendingImageDataBytes = null;
        _isWaitingForRotation = false;
        _isBusy = false;
      }
    } catch (e, stacktrace) {
      print(
          "****** ObjectDetectionView: Error processing image: $e\n$stacktrace");
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
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_initializationErrorMsg!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center),
      ));
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
            if (_processedObjects.isNotEmpty &&
                _lastImageSize != null &&
                _imageRotation != null &&
                _screenSize != null)
              CustomPaint(
                size: parentSize,
                painter: ObjectPainter(
                  objects:
                      _processedObjects.map((info) => info.object).toList(),
                  imageSize: _lastImageSize!,
                  screenSize: _screenSize!,
                  rotation: _imageRotation!,
                  cameraLensDirection:
                      widget.cameras[_cameraIndex].lensDirection,
                  cameraPreviewAspectRatio: cameraAspectRatio,
                  showNameTags: false, // NameTag 그리지 않음
                ),
              ),
          ],
        );
      },
    );
  }
}

// --- From camera_screen.dart (Main Screen Class) ---
class RealtimeObjectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RealtimeObjectDetectionScreen({Key? key, required this.cameras})
      : super(key: key);

  @override
  _RealtimeObjectDetectionScreenState createState() =>
      _RealtimeObjectDetectionScreenState();
}
