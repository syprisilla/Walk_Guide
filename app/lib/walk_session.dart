import 'package:hive/hive.dart';
part 'walk_session.g.dart';

@HiveType(typeId: 0)
class WalkSession {
  @HiveField(0)
  final DateTime startTime;

  @HiveField(1)
  final DateTime endTime;

  @HiveField(2)
  final int stepCount;

  @HiveField(3)
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

  String getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
