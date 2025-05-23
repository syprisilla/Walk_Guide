// lib/ObjectDetection/mlkit_object_detection.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui'; // Required for Size
import 'dart:io' show Platform;

import 'package:flutter/services.dart'; // Required for RootIsolateToken, BackgroundIsolateBinaryMessenger
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
// IsolateDataHolder 정의를 가져옵니다. camera_screen.dart 또는 공통 파일에서 가져올 수 있습니다.
import 'camera_screen.dart' show IsolateDataHolder;

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
      } catch(e) {
        print("****** ImageRotationIsolate: Error sending shutdown ack: $e");
      }
      // Isolate.current.kill()을 여기서 호출하면 ack 메시지가 전송되지 않을 수 있습니다.
      // 메인 스레드에서 kill을 호출하도록 하거나, Isolate.exit()를 고려합니다.
      // 여기서는 일단 ack 전송 후 종료되도록 둡니다. 메인에서 kill 할 것입니다.
      return;
    }
    try {
      if (message is Map<String, dynamic>) {
        final int sensorOrientation = message['sensorOrientation'];
        final int deviceOrientationIndex = message['deviceOrientationIndex'];
        final DeviceOrientation deviceOrientation = DeviceOrientation.values[deviceOrientationIndex];

        final InputImageRotation rotation = _calculateRotation(sensorOrientation, deviceOrientation);
        if (!isShuttingDown) mainSendPort.send(rotation);
      } else {
        throw Exception("Invalid message type for rotation isolate: ${message.runtimeType}");
      }
    } catch (e, stacktrace) {
      print('****** Rotation Isolate Error: $e\n$stacktrace');
      if (!isShuttingDown) mainSendPort.send(['Error from RotationIsolate', e.toString()]);
    }
  });
}

// _calculateRotation 함수는 이전과 동일하게 유지합니다.
InputImageRotation _calculateRotation(int sensorOrientation, DeviceOrientation deviceOrientation) {
  if (Platform.isIOS) {
    // iOS의 경우, 화면 방향과 센서 방향을 고려하여 회전 값을 결정해야 합니다.
    // Flutter camera plugin v0.10.x 이후 iOS에서 이미지 스트림은 항상 portrait 방향으로 전달됩니다 (sensorOrientation 무관).
    // 따라서 deviceOrientation에 따라 이미지를 ML Kit에 맞게 회전시켜야 합니다.
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        return InputImageRotation.rotation0deg; // 이미지가 이미 올바른 방향
      case DeviceOrientation.landscapeLeft:
        return InputImageRotation.rotation270deg; // 시계 반대 방향 90도
      case DeviceOrientation.portraitDown:
        return InputImageRotation.rotation180deg; // 180도
      case DeviceOrientation.landscapeRight:
        return InputImageRotation.rotation90deg; // 시계 방향 90도
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  // Android
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
  // sensorOrientation은 카메라 센서의 물리적 방향입니다.
  // ML Kit은 이미지가 "upright" 상태일 때를 기준으로 하므로,
  // (센서 방향 - 화면 보정치 + 360) % 360 으로 최종 회전값을 계산합니다.
  int resultRotationDegrees = (sensorOrientation - rotationCompensation + 360) % 360;

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
      print('****** Unknown rotation degrees: $resultRotationDegrees. Defaulting to 0deg.');
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
    print("****** Detection Isolate: RootIsolateToken is null. ML Kit might fail.");
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
        await objectDetector.close(); // Isolate 내부의 ObjectDetector 닫기
        print("****** DetectionIsolate: Isolate-specific ObjectDetector closed.");
      } catch (e, stacktrace) {
        print("****** DetectionIsolate: Error closing ObjectDetector: $e\n$stacktrace");
      }
      isolateReceivePort.close();
      try {
         mainSendPort.send('isolate_shutdown_ack_detection');
      } catch(e) {
         print("****** DetectionIsolate: Error sending shutdown ack: $e");
      }
      // 메인 스레드에서 kill을 호출하도록 유도합니다.
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
            InputImageFormatValue.fromRawValue(formatRaw) ?? InputImageFormat.nv21;

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
        if (!isShuttingDown) mainSendPort.send(['Error from DetectionIsolate', e.toString()]);
      }
    } else {
        print('****** Detection Isolate received invalid message type: ${message.runtimeType}');
        if (!isShuttingDown) mainSendPort.send(['Error from DetectionIsolate', 'Invalid message type: ${message.runtimeType}']);
    }
  });
}