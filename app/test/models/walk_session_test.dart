import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/models/walk_session.dart';

void main() {
  group('WalkSession 모델 테스트', () {
    final start = DateTime(2024, 6, 1, 9, 0);
    final end = DateTime(2024, 6, 1, 9, 30);

    test('객체 생성 및 필드 확인', () {
      final session = WalkSession(
        startTime: start,
        endTime: end,
        stepCount: 2000,
        averageSpeed: 1.5,
      );

      expect(session.startTime, start);
      expect(session.endTime, end);
      expect(session.stepCount, 2000);
      expect(session.averageSpeed, 1.5);
    });

    test('toString() 출력 확인', () {
      final session = WalkSession(
        startTime: start,
        endTime: end,
        stepCount: 1000,
        averageSpeed: 1.0,
      );

      final result = session.toString();
      expect(result, contains('WalkSession'));
      expect(result, contains('steps: 1000'));
      expect(result, contains('avgSpeed: 1.00'));
    });

    test('toJson() 직렬화 확인', () {
      final session = WalkSession(
        startTime: start,
        endTime: end,
        stepCount: 1500,
        averageSpeed: 1.2,
      );

      final json = session.toJson();
      expect(json['startTime'], start.toIso8601String());
      expect(json['endTime'], end.toIso8601String());
      expect(json['stepCount'], 1500);
      expect(json['averageSpeed'], 1.2);
    });

    test('fromJson() 역직렬화 확인', () {
      final json = {
        'startTime': start.toIso8601String(),
        'endTime': end.toIso8601String(),
        'stepCount': 1800,
        'averageSpeed': 1.4,
      };

      final session = WalkSession.fromJson(json);
      expect(session.startTime, start);
      expect(session.endTime, end);
      expect(session.stepCount, 1800);
      expect(session.averageSpeed, 1.4);
    });

    test('getDateKey() 날짜 키 생성', () {
      final session = WalkSession(
        startTime: start,
        endTime: end,
        stepCount: 1000,
        averageSpeed: 1.0,
      );

      final key = session.getDateKey(DateTime(2024, 6, 7));
      expect(key, '2024-06-07');
    });
  });
}
