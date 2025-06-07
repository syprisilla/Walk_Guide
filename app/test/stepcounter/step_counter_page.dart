import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/step_counter_page.dart';
import 'package:camera/camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StepCounterPage 테스트', () {
    testWidgets('카메라가 없을 때 UI 렌더링 확인', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: StepCounterPage(cameras: []),
      ));

      expect(find.textContaining('카메라를 사용할 수 없습니다'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('걸음 수, 속도 정보 UI 요소 렌더링 확인', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: StepCounterPage(cameras: []),
      ));

      expect(find.textContaining('걸음'), findsOneWidget);
      expect(find.text('평균 속도'), findsOneWidget);
      expect(find.text('실시간 속도'), findsOneWidget);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('AppBar가 정상 렌더링되는지 확인', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: StepCounterPage(cameras: []),
      ));

      expect(find.text('보행 중'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
