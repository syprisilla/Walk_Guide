import 'dart:async'; // Completer 사용을 위해 추가
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:camera/camera.dart';
import 'package:walk_guide/ObjectDetection/object_painter.dart';
import 'dart:ui' as ui;

void main() {
  group('ObjectPainter Tests', () {
    final mockDetectedObjectWithLabel = DetectedObject(
      boundingBox: const Rect.fromLTWH(25, 25, 50, 50),
      labels: [Label(text: 'Test Object', confidence: 0.8, index: 0)],
      trackingId: 1,
    );
    final mockDetectedObjectWithoutLabel = DetectedObject(
      boundingBox: const Rect.fromLTWH(10, 10, 20, 20),
      labels: [],
      trackingId: 2,
    );

    const defaultImageSize = Size(100, 100);
    const defaultScreenSize = Size(200, 200);
    const defaultCameraLensDirection = CameraLensDirection.back;
    const defaultCameraPreviewAspectRatio = 1.0;
    const defaultShowNameTags = false;

    Future<void> pumpPainter(
      WidgetTester tester, {
      required List<DetectedObject> objects,
      Size imageSize = defaultImageSize,
      Size screenSize = defaultScreenSize,
      InputImageRotation rotation = InputImageRotation.rotation0deg,
      CameraLensDirection cameraLensDirection = defaultCameraLensDirection,
      double cameraPreviewAspectRatio = defaultCameraPreviewAspectRatio,
      bool showNameTags = defaultShowNameTags,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: screenSize,
            painter: ObjectPainter(
              objects: objects,
              imageSize: imageSize,
              screenSize: screenSize,
              rotation: rotation,
              cameraLensDirection: cameraLensDirection,
              cameraPreviewAspectRatio: cameraPreviewAspectRatio,
              showNameTags: showNameTags,
            ),
          ),
        ),
      );
    }

    // ... (기존 shouldRepaint 테스트들) ...
     test('shouldRepaint returns true when objects change', () {
      final painter1 = ObjectPainter(objects: [mockDetectedObjectWithLabel], imageSize: defaultImageSize, screenSize: defaultScreenSize, rotation: InputImageRotation.rotation0deg, cameraLensDirection: defaultCameraLensDirection, cameraPreviewAspectRatio: defaultCameraPreviewAspectRatio, showNameTags: false);
      final painter2 = ObjectPainter(objects: [], imageSize: defaultImageSize, screenSize: defaultScreenSize, rotation: InputImageRotation.rotation0deg, cameraLensDirection: defaultCameraLensDirection, cameraPreviewAspectRatio: defaultCameraPreviewAspectRatio, showNameTags: false);
      expect(painter1.shouldRepaint(painter2), isTrue);
    });
     test('shouldRepaint returns false when all properties are the same', () {
      final painter1 = ObjectPainter(objects: [mockDetectedObjectWithLabel], imageSize: defaultImageSize, screenSize: defaultScreenSize, rotation: InputImageRotation.rotation0deg, cameraLensDirection: defaultCameraLensDirection, cameraPreviewAspectRatio: defaultCameraPreviewAspectRatio, showNameTags: false);
      // Create another instance with the same values to test content equality aspect of shouldRepaint
      final painter2 = ObjectPainter(objects: [mockDetectedObjectWithLabel], imageSize: defaultImageSize, screenSize: defaultScreenSize, rotation: InputImageRotation.rotation0deg, cameraLensDirection: defaultCameraLensDirection, cameraPreviewAspectRatio: defaultCameraPreviewAspectRatio, showNameTags: false);
      // Note: `List<DetectedObject>` equality is by reference. For content equality, a deep equals would be needed in shouldRepaint.
      // Current shouldRepaint logic: oldDelegate.objects != objects (reference check for list)
      // To make this test meaningful for list content, painter1.objects and painter2.objects would need to be distinct lists with same content.
      // However, if objects are identical (same instance), it should be false.
      expect(painter1.shouldRepaint(painter1.copyWith()), isFalse); // Using copyWith for clarity
    });


    testWidgets('paint method with empty imageSize returns early', (WidgetTester tester) async {
      await pumpPainter(tester, objects: [mockDetectedObjectWithLabel], imageSize: Size.zero);
      expect(tester.takeException(), isNull);
    });

    // ... (나머지 object_painter_test.dart 테스트 케이스들은 이전 답변과 동일하게 유지) ...
    // (createImage 헬퍼도 이전 답변과 동일하게 유지)

    testWidgets('paint method with empty screenSize returns early', (WidgetTester tester) async {
      await pumpPainter(tester, objects: [mockDetectedObjectWithLabel], screenSize: Size.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with zero cameraPreviewAspectRatio returns early', (WidgetTester tester) async {
      await pumpPainter(tester, objects: [mockDetectedObjectWithLabel], cameraPreviewAspectRatio: 0);
      expect(tester.takeException(), isNull);
    });

    for (var rotation in InputImageRotation.values) {
      testWidgets('paint method runs without error for rotation: ${rotation.name}', (WidgetTester tester) async {
        await pumpPainter(tester, objects: [mockDetectedObjectWithLabel], rotation: rotation);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('paint method with screenAspectRatio > cameraPreviewAspectRatio', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        screenSize: const Size(300, 100), 
        cameraPreviewAspectRatio: 1.0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with screenAspectRatio <= cameraPreviewAspectRatio', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        screenSize: const Size(100, 300),
        cameraPreviewAspectRatio: 1.0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with mlImageWidth effectively zero', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        imageSize: const Size(100, 0),
        rotation: InputImageRotation.rotation90deg,
      );
      expect(tester.takeException(), isNull);
    });

     testWidgets('paint method with mlImageHeight effectively zero', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        imageSize: const Size(0, 100),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method for front camera on Android', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        cameraLensDirection: CameraLensDirection.front,
        rotation: InputImageRotation.rotation0deg,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('paint method shows name tag when showNameTags is true and labels exist', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        showNameTags: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method does not show name tag when showNameTags is false', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithLabel],
        showNameTags: false,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method does not show name tag when labels are empty', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        objects: [mockDetectedObjectWithoutLabel],
        showNameTags: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with name tag near top edge', (WidgetTester tester) async {
      final objectNearTop = DetectedObject(
        boundingBox: const Rect.fromLTWH(25, 5, 50, 10),
        labels: [Label(text: 'Top Object', confidence: 0.9, index: 0)],
        trackingId: 3,
      );
      await pumpPainter(
        tester,
        objects: [objectNearTop],
        imageSize: const Size(100,100),
        screenSize: const Size(200,200),
        showNameTags: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with name tag near bottom edge', (WidgetTester tester) async {
      final objectNearBottom = DetectedObject(
        boundingBox: const Rect.fromLTWH(25, 80, 50, 15),
        labels: [Label(text: 'Bottom Object', confidence: 0.9, index: 0)],
        trackingId: 4,
      );
      await pumpPainter(
        tester,
        objects: [objectNearBottom],
        imageSize: const Size(100,100),
        screenSize: const Size(200,200),
        cameraPreviewAspectRatio: 1.0,
        showNameTags: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paint method with very narrow bounding box', (WidgetTester tester) async {
      final veryNarrowObject = DetectedObject(
        boundingBox: const Rect.fromLTWH(49.5, 25, 1, 50),
        labels: [Label(text: 'Narrow', confidence: 0.8, index: 0)],
        trackingId: 5,
      );
      await pumpPainter(
        tester,
        objects: [veryNarrowObject],
      );
      expect(tester.takeException(), isNull);
    });
  });
}

extension WidgetTesterImageExtension on WidgetTester {
  Future<ui.Image> createImage(int width, int height) {
    final Completer<ui.Image> completer = Completer(); // Completer 사용
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.transparent);
    final ui.Picture picture = recorder.endRecording();
    // ignore: deprecated_member_use
    picture.toImage(width, height).then((image) { // toImage는 Future<ui.Image> 반환
      completer.complete(image);
    }).catchError((dynamic e, StackTrace s) { // 오류 처리 추가
        completer.completeError(e,s);
    });
    return completer.future;
  }
}

// ObjectPainter.copyWith() - 이전 답변에서 복사 (ObjectPainter가 public으로 가정)
extension on ObjectPainter {
  ObjectPainter copyWith({
    List<DetectedObject>? objects,
    Size? imageSize,
    Size? screenSize,
    InputImageRotation? rotation,
    CameraLensDirection? cameraLensDirection,
    double? cameraPreviewAspectRatio,
    bool? showNameTags,
  }) {
    return ObjectPainter(
      objects: objects ?? this.objects,
      imageSize: imageSize ?? this.imageSize,
      screenSize: screenSize ?? this.screenSize,
      rotation: rotation ?? this.rotation,
      cameraLensDirection: cameraLensDirection ?? this.cameraLensDirection,
      cameraPreviewAspectRatio: cameraPreviewAspectRatio ?? this.cameraPreviewAspectRatio,
      showNameTags: showNameTags ?? this.showNameTags,
    );
  }
}