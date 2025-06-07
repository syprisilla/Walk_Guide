import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:walk_guide/ObjectDetection/camera_initialization_ui.dart'; //
import 'package:walk_guide/ObjectDetection/camera_screen.dart'; //

// Mock CameraDescription for testing
const mockCamera = CameraDescription(
  name: 'mock_cam_0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MyApp (CameraInitializationUI) Tests', () {
    testWidgets('Shows error message when no cameras are available', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp(cameras: [])); //

      // Verify the error message is displayed.
      expect(find.text('사용 가능한 카메라가 없습니다.\n앱 권한을 확인하거나 앱을 재시작해주세요.'), findsOneWidget);
      expect(find.byType(RealtimeObjectDetectionScreen), findsNothing);
    });

    testWidgets('Shows RealtimeObjectDetectionScreen when cameras are available', (WidgetTester tester) async {
      // For this test to pass without fully initializing RealtimeObjectDetectionScreen's
      // complex dependencies, RealtimeObjectDetectionScreen itself should be mockable
      // or its dependencies handled. Here, we just check if it's attempted to be rendered.
      await tester.pumpWidget(const MyApp(cameras: [mockCamera])); //

      // Verify that RealtimeObjectDetectionScreen is part of the widget tree.
      expect(find.byType(RealtimeObjectDetectionScreen), findsOneWidget);
      expect(find.text('사용 가능한 카메라가 없습니다.\n앱 권한을 확인하거나 앱을 재시작해주세요.'), findsNothing);
    });
  });
}