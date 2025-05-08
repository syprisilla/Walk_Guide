class RealTimeSpeedService {
  static List<DateTime> recentSteps = [];

  static double getSpeed() {
    final now = DateTime.now();
    recentSteps =
        recentSteps.where((t) => now.difference(t).inSeconds <= 3).toList();
    int count = recentSteps.length;
    return count * 0.7 / 3;
  }

  static void recordStep() {
    recentSteps.add(DateTime.now());
  }

  static void clear() {
    recentSteps.clear();
  }
}
