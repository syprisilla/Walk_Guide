import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/nickname/nickname_input_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NicknameInputPage 테스트', () {
    testWidgets('페이지 기본 요소 렌더링 확인', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NicknameInputPage()));

      expect(find.text('닉네임 입력'), findsOneWidget);
      expect(find.text('사용할 닉네임을 입력해주세요.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('저장하고 시작하기'), findsOneWidget);
    });

    testWidgets('닉네임 입력 필드에 텍스트 입력 가능', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NicknameInputPage()));

      final textField = find.byType(TextField);
      await tester.enterText(textField, '테스트닉네임');
      await tester.pump();

      expect(find.text('테스트닉네임'), findsOneWidget);
    });

    testWidgets('저장 버튼을 누르면 로딩 인디케이터 나타남 (currentUser 없어서 저장은 안 됨)',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NicknameInputPage()));

      final textField = find.byType(TextField);
      await tester.enterText(textField, '테스트닉네임');

      await tester.tap(find.text('저장하고 시작하기'));
      await tester.pump(); // setState 반영

      // user == null 이므로 로직 내부까지는 못 들어가지만, _isSaving 은 true로 바뀌고 로딩 인디케이터가 나옴
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('TextField에 포커스 이동 시도', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NicknameInputPage()));

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      expect(textField, findsOneWidget);
    });

    testWidgets('저장 버튼이 비활성화되는 조건 없음 확인 (_isSaving=false)',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NicknameInputPage()));
      final saveButton = find.byType(ElevatedButton);

      // 기본 상태에서는 활성화된 버튼
      expect(tester.widget<ElevatedButton>(saveButton).onPressed != null, true);
    });
  });
}
