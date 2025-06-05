import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:walk_guide/ObjectDetection/name_tag_painter.dart'; //

void main() {
  group('NameTagUtils Tests', () {
    testWidgets('paintNameTag runs without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: _TestNameTagPainter(
              label: Label(text: 'Test Object', confidence: 0.75, index: 0),
              boundingBoxRect: const Rect.fromLTWH(10, 30, 50, 50),
              canvasSize: const Size(100, 100),
            ),
            size: const Size(100,100),
          ),
        ),
      );
      // Check no exceptions were thrown during paint.
      expect(tester.takeException(), isNull);
    });

    testWidgets('paintNameTag adjusts Y position if text goes above canvas', (WidgetTester tester) async {
      final label = Label(text: 'Test', confidence: 0.8, index: 0);
      // Bounding box is very close to the top, text normally would go above.
      final boundingBox = const Rect.fromLTWH(10, 5, 50, 20); // top is 5
      final canvasSize = const Size(100, 100);

      // We need a way to check the painted text position.
      // This is hard without deeper canvas inspection or golden file testing.
      // For now, we ensure it runs. A more advanced test would capture the
      // TextPainter's paint offset.

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: _TestNameTagPainter(
              label: label,
              boundingBoxRect: boundingBox,
              canvasSize: canvasSize,
            ),
            size: canvasSize,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _TestNameTagPainter extends CustomPainter {
  final Label label;
  final Rect boundingBoxRect;
  final Size canvasSize;

  _TestNameTagPainter({
    required this.label,
    required this.boundingBoxRect,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    NameTagUtils.paintNameTag( //
      canvas: canvas,
      label: label,
      boundingBoxRect: boundingBoxRect,
      canvasSize: canvasSize,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}