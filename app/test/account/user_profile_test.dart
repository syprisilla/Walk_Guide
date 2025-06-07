import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/account/user_profile.dart';
import 'package:walk_guide/models/walk_session.dart';

void main() {
  group('UserProfile 테스트', () {
    test('빈 세션 리스트 처리', () {
      final profile = UserProfile.fromSessions([]);
      expect(profile.avgSpeed, 0.0);
      expect(profile.avgSessionDuration, 0.0);
    });

    test('세션 데이터를 통한 평균 계산', () {
      final sessions = [
        WalkSession(
          startTime: DateTime(2024, 6, 1, 10, 0),
          endTime: DateTime(2024, 6, 1, 10, 30),
          stepCount: 1500,
          averageSpeed: 1.0,
        ),
        WalkSession(
          startTime: DateTime(2024, 6, 1, 11, 0),
          endTime: DateTime(2024, 6, 1, 11, 30),
          stepCount: 1800,
          averageSpeed: 1.5,
        ),
      ];

      final profile = UserProfile.fromSessions(sessions);
      expect(profile.avgSpeed, closeTo(1.25, 0.001));
      expect(profile.avgSessionDuration, 1800); // 30분 in seconds
    });

    test('getGuidanceDelay 속도별 조건 확인', () {
      final slowUser = UserProfile.fromSessions([
        WalkSession(
          startTime: DateTime.now(),
          endTime: DateTime.now().add(const Duration(minutes: 1)),
          stepCount: 100,
          averageSpeed: 0.4,
        ),
      ]);
      expect(slowUser.getGuidanceDelay(), const Duration(seconds: 2));

      final normalUser = UserProfile.fromSessions([
        WalkSession(
          startTime: DateTime.now(),
          endTime: DateTime.now().add(const Duration(minutes: 1)),
          stepCount: 100,
          averageSpeed: 1.0,
        ),
      ]);
      expect(normalUser.getGuidanceDelay(), const Duration(milliseconds: 1500));

      final fastUser = UserProfile.fromSessions([
        WalkSession(
          startTime: DateTime.now(),
          endTime: DateTime.now().add(const Duration(minutes: 1)),
          stepCount: 100,
          averageSpeed: 1.5,
        ),
      ]);
      expect(fastUser.getGuidanceDelay(), const Duration(seconds: 1));
    });
  });
}
