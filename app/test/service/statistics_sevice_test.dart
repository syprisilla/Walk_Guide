import 'package:flutter_test/flutter_test.dart';
import 'package:walk_guide/services/statistics_service.dart';
import 'package:walk_guide/models/walk_session.dart';

void main() {
  group('StatisticsService', () {
    final now = DateTime.now();
    final todaySession = WalkSession(
      startTime: now.subtract(const Duration(hours: 1)),
      endTime: now,
      stepCount: 1000,
      averageSpeed: 1.2,
    );
    final oldSession = WalkSession(
      startTime: now.subtract(const Duration(days: 7)),
      endTime: now.subtract(const Duration(days: 7, hours: -1)),
      stepCount: 500,
      averageSpeed: 1.0,
    );

    final sessions = [todaySession, oldSession];

    test('calculateStats returns correct daily and weekly steps', () {
      final result = StatisticsService.calculateStats(sessions);
      expect(result['daily_steps'], 1000);
      expect(result['weekly_steps'], 1000); // oldSession은 범위 밖
    });

    test('getWeeklyStepData returns correct per-day steps', () {
      final result = StatisticsService.getWeeklyStepData(sessions);
      expect(result.length, 7); // 7일치
      final todayKey = StatisticsService.formatDateKey(
        DateTime(now.year, now.month, now.day),
      );
      expect(result[todayKey], 1000);
    });
  });
}
