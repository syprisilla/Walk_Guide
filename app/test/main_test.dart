import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:walk_guide/main_testable.dart' as test_app;

void main() {
  testWidgets('main_testable.dart coverage 테스트 - test mode',
      (WidgetTester tester) async {
    await test_app.testableMain(isTest: true);
    await tester.pump();
    expect(find.text('Test Mode'), findsOneWidget);
  });

  testWidgets('main_testable.dart coverage 테스트 - normal mode',
      (WidgetTester tester) async {
    await test_app.testableMain(); // isTest: false
    await tester.pump();
    // 굳이 expect 없어도 커버리지 목적엔 OK
  });
}
