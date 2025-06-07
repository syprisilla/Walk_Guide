import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:walk_guide/ObjectDetection/name_tag_painter.dart';

void main() {
  group('NameTagUtils Tests', () {
    // 테스트에서 사용할 기본 객체 레이블
    final testLabel = Label(text: 'Test Object', confidence: 0.75, index: 0);

    // painter를 생성하고 pump하는 헬퍼 함수
    Future<void> pumpPainter(
      WidgetTester tester, {
      required Label label,
      required Rect boundingBoxRect,
      required Size canvasSize,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: canvasSize,
            painter: _TestNameTagPainter(
              label: label,
              boundingBoxRect: boundingBoxRect,
              canvasSize: canvasSize,
            ),
          ),
        ),
      );
    }

    testWidgets('paintNameTag가 일반적인 경우 오류 없이 실행되어야 함', (WidgetTester tester) async {
      await pumpPainter(
        tester,
        label: testLabel,
        boundingBoxRect: const Rect.fromLTWH(20, 20, 40, 40),
        canvasSize: const Size(100, 100),
      );
      // 예외가 발생하지 않았는지 확인
      expect(tester.takeException(), isNull);
    });

    testWidgets('객체가 화면 상단 가장자리에 있을 때 위치 조정 로직이 실행되어야 함', (WidgetTester tester) async {
      // 이름표가 화면 위로 벗어나는 경우 (textY < 0)
      await pumpPainter(
        tester,
        label: testLabel,
        boundingBoxRect: const Rect.fromLTWH(20, 5, 40, 40), // y=5, 상단에 위치
        canvasSize: const Size(100, 100),
      );
      expect(tester.takeException(), isNull);
    });

    // --- 커버리지 향상을 위한 신규 테스트 케이스 ---
    testWidgets('캔버스 높이가 매우 작고 객체가 상단에 있을 때 중첩된 위치 조정 로직이 실행되어야 함', (WidgetTester tester) async {
      // 이 테스트는 textY < 0 이면서 동시에 textY + textPainter.height > canvasSize.height 인
      // 특수한 경우를 커버하여 누락된 라인을 실행시킵니다.
      await pumpPainter(
        tester,
        label: testLabel,
        boundingBoxRect: const Rect.fromLTWH(10, 5, 80, 10), // y=5 (상단), 높이=10
        canvasSize: const Size(100, 20), // 캔버스 높이가 매우 작음
      );
      
      // 이 시나리오에서 모든 위치 조정 로직이 오류 없이 실행되는지 확인
      expect(tester.takeException(), isNull);
    });
  });
}

// 테스트를 위한 CustomPainter 래퍼 클래스
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
    NameTagUtils.paintNameTag(
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