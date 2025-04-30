class WalkSession {
  final DateTime startTime;
  final DateTime endTime;
  final int stepCount;
  final double averageSpeed;

  WalkSession({
    required this.startTime,
    required this.endTime,
    required this.stepCount,
    required this.averageSpeed,
  });

  @override
  String toString() {
    return 'WalkSession(start: $startTime, end: $endTime, steps: $stepCount, avgSpeed: ${averageSpeed.toStringAsFixed(2)} m/s)';
  }
}
