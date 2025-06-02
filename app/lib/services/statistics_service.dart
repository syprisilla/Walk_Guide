import 'package:walk_guide/walk_session.dart';

class StatisticsService {
  static Map<String, dynamic> calculateStats(List<WalkSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 6));

    int todaySteps = 0;
    int weekSteps = 0;

    for (final session in sessions) {
      final date = DateTime(session.startTime.year, session.startTime.month, session.startTime.day);

      if (!date.isBefore(sevenDaysAgo)) {
        weekSteps += session.stepCount;

        if (date == today) {
          todaySteps += session.stepCount;
        }
      }
    }

    return {
      'daily_steps': todaySteps,
      'weekly_steps': weekSteps,
    };
  }
}
