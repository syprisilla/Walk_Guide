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
