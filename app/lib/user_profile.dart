import 'package:walk_guide/walk_session.dart';

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
}
