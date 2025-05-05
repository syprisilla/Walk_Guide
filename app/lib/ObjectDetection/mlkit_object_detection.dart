import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';

ObjectDetector initializeObjectDetector() {
  print("Initializing ML Kit detector...");
  final options = ObjectDetectorOptions(
    mode: DetectionMode.stream,
    classifyObjects: true,
    multipleObjects: true,
  );
  return ObjectDetector(options: options);
}

@pragma('vm:entry-point')
void detectObjectsIsolateEntry(List<Object> args) {
  final SendPort mainSendPort = args[0] as SendPort;
  final RootIsolateToken rootIsolateToken = args[1] as RootIsolateToken;

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

  final ReceivePort receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is List) {
      try {
        final Uint8List bytes = message[0];
        final int width = message[1];
        final int height = message[2];
        final InputImageRotation rotation = message[3];
        final int formatRaw = message[4];
        final int bytesPerRow = message[5];

        final List<DetectedObject> objects = await _detectObjectsImpl(
            bytes, width, height, rotation, formatRaw, bytesPerRow);
        mainSendPort.send(objects);
      } catch (e, stacktrace) {
        print("****** Error in detectObjectsIsolateEntry listen: $e");
        print(stacktrace);
        mainSendPort.send(['Error from Detection Isolate', e.toString()]);
      }
    }
  });
}

Future<List<DetectedObject>> _detectObjectsImpl(
    Uint8List bytes,
    int width,
    int height,
    InputImageRotation rotation,
    int formatRaw,
    int bytesPerRow) async {
  final options = ObjectDetectorOptions(
    mode: DetectionMode.single,
    classifyObjects: true,
    multipleObjects: true,
  );
  final ObjectDetector objectDetector = ObjectDetector(options: options);

  final inputImage = InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: InputImageFormatValue.fromRawValue(formatRaw) ??
          InputImageFormat.nv21,
      bytesPerRow: bytesPerRow,
    ),
  );

  try {
    final List<DetectedObject> objects =
        await objectDetector.processImage(inputImage);
    return objects;
  } catch (e, stacktrace) {
    print("****** Error processing image in _detectObjectsImpl: $e");
    print(stacktrace);
    return <DetectedObject>[];
  } finally {
    await objectDetector.close();
  }
}

@pragma('vm:entry-point')
void getImageRotationIsolateEntry(SendPort sendPort) {
  final ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is List && message.length == 2) {
      try {
        final int sensorOrientation = message[0];
        final DeviceOrientation deviceOrientation = message[1];
        final InputImageRotation? rotation =
            _getImageRotationImpl(sensorOrientation, deviceOrientation);
        sendPort.send(rotation);
      } catch (e, stacktrace) {
        print("****** Error in getImageRotationIsolateEntry listen: $e");
        print(stacktrace);
        sendPort.send(['Error from Rotation Isolate', e.toString()]);
      }
    }
  });
}

InputImageRotation? _getImageRotationImpl(
    int sensorOrientation, DeviceOrientation deviceOrientation) {
  if (Platform.isIOS) {
    int deviceOrientationAngle = 0;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceOrientationAngle = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceOrientationAngle = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceOrientationAngle = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceOrientationAngle = 270;
        break;
      default:
        break;
    }
    var compensatedRotation =
        (sensorOrientation + deviceOrientationAngle) % 360;
    return _rotationIntToInputImageRotation(compensatedRotation);
  } else {
    int deviceOrientationAngle = 0;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceOrientationAngle = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceOrientationAngle = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceOrientationAngle = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceOrientationAngle = 270;
        break;
      default:
        break;
    }
    var compensatedRotation =
        (sensorOrientation - deviceOrientationAngle + 360) % 360;
    return _rotationIntToInputImageRotation(compensatedRotation);
  }
}

InputImageRotation _rotationIntToInputImageRotation(int rotation) {
  switch (rotation) {
    case 0:
      return InputImageRotation.rotation0deg;
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}
