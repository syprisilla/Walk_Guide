import 'package:hive/hive.dart';

class RealTimeSpeedService {
  static const String boxName = 'recent_steps';
  static const Duration window = Duration(seconds: 3);
  static const Duration holdTime = Duration(seconds: 5);

  static double _lastSpeed = 0.0;
  static DateTime? _lastUpdateTime;

  static void recordStep([DateTime? time]) {
    final box = Hive.box<DateTime>(boxName);
    box.add(time ?? DateTime.now()); // 외부에서 받은 시간 사용, 없으면 현재 시간
  }

  static double getSpeed() {
    final box = Hive.box<DateTime>(boxName);
    final now = DateTime.now();

    // 최근 걸음 리스트 필터링
    final validSteps = box.values
        .where((t) => now.difference(t).inSeconds <= window.inSeconds)
        .toList();

    // 최근 걸음 수로 속도 계산
    final count = validSteps.length;
    final speed = count * 0.7 / window.inSeconds;

    if (speed > 0) {
      _lastSpeed = speed;
      _lastUpdateTime = now;
      return speed;
    }

    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inSeconds <= holdTime.inSeconds) {
      return _lastSpeed;
    }

    _lastSpeed = 0.0;
    return 0.0;
  }

  static void clear() {
    final box = Hive.box<DateTime>(boxName);
    box.clear();
    _lastSpeed = 0.0;
    _lastUpdateTime = null;
  }

  static bool get hasRecentSteps {
    final box = Hive.box<DateTime>(boxName);
    return box.isNotEmpty;
  }
}
