import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui'; 
import 'dart:io' show Platform;

import 'package:flutter/services.dart'; 
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
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

InputImageRotation _calculateRotation(int sensorOrientation, DeviceOrientation deviceOrientation) {
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
        await objectDetector.close();
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