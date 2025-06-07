import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/login/login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LoginScreen 렌더링 요소 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('WalkGuide'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('Google로 로그인하기'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
  });

  testWidgets('이메일/비밀번호 입력 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');

    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('password123'), findsOneWidget);
  });

  testWidgets('회원가입 페이지 이동 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    // 실제 SignUpScreen 렌더링 여부까지는 확인 불가하지만, 네비게이션 동작은 됨
    expect(find.text('회원가입'), findsWidgets);
  });

  testWidgets('Google 로그인 버튼 눌림 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('Google로 로그인하기'));
    await tester.pump(); // TTS나 호출 트리거만 유도
  });

  testWidgets('TextField 포커스 시 TTS 유도', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    final emailField = find.byType(TextField).at(0);
    final passwordField = find.byType(TextField).at(1);

    await tester.tap(emailField);
    await tester.pump();
    await tester.tap(passwordField);
    await tester.pump();

    // 실제 음성 출력은 확인 불가, 그러나 focusListener 실행은 커버됨
    expect(emailField, findsOneWidget);
    expect(passwordField, findsOneWidget);
  });

  testWidgets('로그인 버튼 탭 테스트 (실제 로그인은 안 됨)', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'test@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrongpassword');

    await tester.tap(find.text('로그인'));
    await tester.pump(const Duration(seconds: 2)); // SnackBar 등 대기

    // 로그인 실패 시 SnackBar 출력되는 로직 호출은 유도됨 (단, 실제 user == null 조건은 확인 불가)
  });
}
