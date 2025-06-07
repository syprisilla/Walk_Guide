import 'package:walk_guide/models/walk_session.dart';

class UserProfile {
  final double avgSpeed;
  final double avgSessionDuration;

  UserProfile._(this.avgSpeed, this.avgSessionDuration);

  factory UserProfile.fromSessions(List<WalkSession> sessions) {
    if (sessions.isEmpty) {
      return UserProfile._(0.0, 0.0);
    }

    final totalSpeed =
        sessions.map((s) => s.averageSpeed).reduce((a, b) => a + b);
    final totalDuration = sessions
        .map((s) => s.endTime.difference(s.startTime).inSeconds)
        .reduce((a, b) => a + b);

    return UserProfile._(
      totalSpeed / sessions.length,
      totalDuration / sessions.length.toDouble(),
    );
  }

  // 사용자 평균 속도에 따라 음성 안내 딜레이 반환
  Duration getGuidanceDelay() {
    if (avgSpeed < 0.5) {
      return const Duration(seconds: 2);
    } else if (avgSpeed < 1.2) {
      return const Duration(milliseconds: 1500);
    } else {
      return const Duration(seconds: 1);
    }
  }
}
