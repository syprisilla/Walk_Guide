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
