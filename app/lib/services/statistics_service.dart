import 'package:walk_guide/walk_session.dart';

class StatisticsService {
  // 오늘과 일주일 간 걸음 수 합산 계산
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

  // 일자별 걸음 수 (BarChart용)
  static Map<String, int> getWeeklyStepData(List<WalkSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 6));

    final Map<String, int> stepMap = {};
    for (int i = 0; i < 7; i++) {
      final date = sevenDaysAgo.add(Duration(days: i));
      final key = _formatDateKey(date);
      stepMap[key] = 0;
    }

    for (final session in sessions) {
      final date = DateTime(session.startTime.year, session.startTime.month, session.startTime.day);
      final key = _formatDateKey(date);
      if (stepMap.containsKey(key)) {
        stepMap[key] = stepMap[key]! + session.stepCount;
      }
    }

    return stepMap;
  }

  // yyyy-MM-dd 형식으로 날짜 문자열 변환
  static String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
