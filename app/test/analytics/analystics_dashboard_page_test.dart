import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:walk_guide/analytics/analytics_dashboard_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/models/walk_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyticsDashboardPage Widget Test', () {
    setUp(() async {
      // Hive 초기화 및 mock 데이터 삽입 (필요시)
      await Hive.initFlutter();
      Hive.registerAdapter(WalkSessionAdapter());
      var box = await Hive.openBox<WalkSession>('walk_sessions');
      await box.clear();
      await box.add(WalkSession(
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
        endTime: DateTime.now(),
        stepCount: 800,
        averageSpeed: 1.0,
      ));
    });

    testWidgets('should display charts and session list',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AnalyticsDashboardPage(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('보행 데이터 분석'), findsOneWidget);
      expect(find.text('오늘 하루 속도 변화'), findsOneWidget);
      expect(find.text('최근 일주일 평균 속도 변화'), findsOneWidget);
      expect(find.text('세션 다시보기'), findsOneWidget);

      // 버튼 존재 확인
      expect(find.text('초기화'), findsOneWidget);
      expect(find.text('백업'), findsOneWidget);
      expect(find.text('복원'), findsOneWidget);
    });
  });
}
