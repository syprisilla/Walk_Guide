// lib/logic/mlkit_logic.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui'; // Size 사용
import 'dart:io' show Platform; // Platform 사용을 위해 dart:io 임포트

import 'package:flutter/services.dart'; // DeviceOrientation, RootIsolateToken, BackgroundIsolateBinaryMessenger
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import '../camera_screen.dart';


ObjectDetector initializeObjectDetector() {
  // feature_nearobject 브랜치의 print 문 선택
  print("Logic: Initializing ObjectDetector...");
  final options = ObjectDetectorOptions(
    mode: DetectionMode.stream, // 스트림(단일 이미지) 모드
    classifyObjects: true,      // 객체 분류 활성화
    multipleObjects: true,      // 다중 객체 감지 활성화
  );
  return ObjectDetector(options: options);
}

// 이미지 회전 계산 Isolate 진입점
// feature_nearobject 브랜치의 getImageRotationIsolateEntry 선택
@pragma('vm:entry-point') // 추가: Isolate 진입점 명시
void getImageRotationIsolateEntry(SendPort mainSendPort) {
  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort); // 메인 Isolate로 Isolate의 SendPort 전송

  isolateReceivePort.listen((dynamic message) {
    try {
      // print("RotationIsolate received: $message"); // 디버깅용 로그
      if (message is Map<String, dynamic>) {
        final int sensorOrientation = message['sensorOrientation'];
        final int deviceOrientationIndex = message['deviceOrientationIndex'];
        final DeviceOrientation deviceOrientation = DeviceOrientation.values[deviceOrientationIndex];
        // final CameraLensDirection lensDirection = CameraLensDirection.values[message['lensDirection']]; // 필요하다면

        final InputImageRotation rotation = _calculateRotation(sensorOrientation, deviceOrientation /*, lensDirection*/);
        mainSendPort.send(rotation);
      } else {
        throw Exception("Invalid message type for rotation isolate: ${message.runtimeType}");
      }
    } catch (e, stacktrace) {
      print('****** Rotation Isolate Error: $e\n$stacktrace');
      mainSendPort.send(['Error from RotationIsolate', e.toString()]); // 오류 정보 전송
    }
  });
}

InputImageRotation _calculateRotation(int sensorOrientation, DeviceOrientation deviceOrientation /*, CameraLensDirection lensDirection */) {
  // print("_calculateRotation: sensor=$sensorOrientation, device=$deviceOrientation"); // 디버깅용 로그
  if (Platform.isIOS) { // dart:io의 Platform 사용
    // iOS는 sensorOrientation이 보통 ML Kit의 InputImageRotation과 직접 매핑됨.
    switch (sensorOrientation) {
      case 0: return InputImageRotation.rotation0deg;
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  // Android 계산 로직
  int rotationCompensation = 0;
  switch (deviceOrientation) {
    case DeviceOrientation.portraitUp:
      rotationCompensation = 0;
      break;
    case DeviceOrientation.landscapeRight: // 홈버튼이 왼쪽 (시계 방향 90도 회전)
      rotationCompensation = 90;
      break;
    case DeviceOrientation.portraitDown:
      rotationCompensation = 180;
      break;
    case DeviceOrientation.landscapeLeft: // 홈버튼이 오른쪽 (반시계 방향 90도 회전 또는 시계방향 270도)
      rotationCompensation = 270;
      break;
    // default: // DeviceOrientation.unknown 등은 portraitUp으로 간주될 수 있음
    //   break;
  }

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


// 객체 탐지 Isolate 진입점
// feature_nearobject 브랜치의 detectObjectsIsolateEntry 선택
@pragma('vm:entry-point') // 추가: Isolate 진입점 명시
void detectObjectsIsolateEntry(IsolateDataHolder isolateDataHolder) {
  final SendPort mainSendPort = isolateDataHolder.mainSendPort;
  final RootIsolateToken? rootIsolateToken = isolateDataHolder.rootIsolateToken;

  final ReceivePort isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort); // 메인 Isolate로 Isolate의 SendPort 전송

  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    print("DetectionIsolate: BackgroundIsolateBinaryMessenger initialized.");
  } else {
    print("****** Detection Isolate: RootIsolateToken is null. ML Kit might fail.");
  }

  // Isolate 내에서 ObjectDetector 인스턴스 생성 및 관리
  final ObjectDetector objectDetector = initializeObjectDetector(); // 옵션은 메인 스레드와 동일
  print("DetectionIsolate: ObjectDetector initialized.");


  isolateReceivePort.listen((dynamic message) async {
    if (message is Map<String, dynamic>) {
      // print("DetectionIsolate received data for processing."); // 디버깅용 로그
      try {
        final Uint8List bytes = message['bytes'];
        final int width = message['width'];
        final int height = message['height'];
        final InputImageRotation rotation = message['rotation']; // 이미 InputImageRotation 타입
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
        // print("DetectionIsolate: Detected ${objects.length} objects."); // 디버깅용 로그
        mainSendPort.send(objects);
      } catch (e, stacktrace) {
        print('****** Detection Isolate processImage Error: $e\n$stacktrace');
        mainSendPort.send(['Error from DetectionIsolate', e.toString()]);
      }
    } else {
       print('****** Detection Isolate received invalid message type: ${message.runtimeType}');
       mainSendPort.send(['Error from DetectionIsolate', 'Invalid message type: ${message.runtimeType}']);
    }
  });
  // Isolate가 지속적으로 메시지를 수신 대기하므로, objectDetector.close()는 Isolate 종료 시점에 처리.
  // (현재는 메인 스레드에서 Isolate.kill()로 종료하므로 명시적 close 어려움)
}

