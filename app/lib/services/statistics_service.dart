import 'package:walk_guide/walk_session.dart';

class StatisticsService {
  static Map<String, dynamic> calculateStats(List<WalkSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 6));

    int todaySteps = 0;
    double todaySpeedSum = 0;
    int todayCount = 0;

    int weekSteps = 0;
    double weekSpeedSum = 0;
    int weekCount = 0;

    for (final session in sessions) {
      final date = DateTime(session.startTime.year, session.startTime.month, session.startTime.day);

      if (!date.isBefore(sevenDaysAgo)) {
        weekSteps += session.stepCount;
        weekSpeedSum += session.averageSpeed;
        weekCount++;

        if (date == today) {
          todaySteps += session.stepCount;
          todaySpeedSum += session.averageSpeed;
          todayCount++;
        }
      }
    }

    return {
      'daily_steps': todaySteps,
      'daily_avg_speed': todayCount > 0 ? todaySpeedSum / todayCount : 0.0,
      'weekly_steps': weekSteps,
      'weekly_avg_speed': weekCount > 0 ? weekSpeedSum / weekCount : 0.0,
    };
  }
}
