import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class HourlySpeed {
  final DateTime time;
  final double averageSpeed;

  HourlySpeed({required this.time, required this.averageSpeed});
}

class FirestoreService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// 걸음 수 저장
  static Future<void> saveDailySteps(int stepCount) async {
    final user = _auth.currentUser;
    if (user == null || stepCount < 0) return;

    final uid = user.uid;
    final now = DateTime.now();
    final dateKey = _dateKey(now);

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_steps')
          .doc(dateKey)
          .set({
        'steps': stepCount,
        'date': Timestamp.fromDate(now),
      });
    } catch (e) {
      debugPrint('❌ saveDailySteps 오류: $e');
    }
  }

  /// 속도 저장
  static Future<void> saveWalkingSpeed(double speed) async {
    final user = _auth.currentUser;
    if (user == null || speed < 0 || speed > 10) return;

    final uid = user.uid;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('walking_data')
          .add({
        'speed': speed,
        'timestamp': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('❌ saveWalkingSpeed 오류: $e');
    }
  }

  /// 통계 저장
  static Future<void> saveAggregateStats(Map<String, dynamic> stats) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!(stats.containsKey('daily_steps') &&
        stats.containsKey('daily_avg_speed') &&
        stats.containsKey('weekly_steps') &&
        stats.containsKey('weekly_avg_speed'))) {
      debugPrint('❌ saveAggregateStats: 필드 누락');
      return;
    }

    final uid = user.uid;
    final now = DateTime.now();
    final dateKey = _dateKey(now);

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('aggregate_stats')
          .doc(dateKey)
          .set({
        'daily_steps': stats['daily_steps'],
        'daily_avg_speed': stats['daily_avg_speed'],
        'weekly_steps': stats['weekly_steps'],
        'weekly_avg_speed': stats['weekly_avg_speed'],
        'timestamp': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('❌ saveAggregateStats 오류: $e');
    }
  }

  /// 오늘 하루 속도 데이터 불러오기 (5분 단위 평균)
  static Future<List<HourlySpeed>> fetchTodaySpeedData() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final uid = user.uid;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('walking_data')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp')
          .get();

      final Map<String, List<double>> grouped = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = (data['timestamp'] as Timestamp).toDate();
        final speed = (data['speed'] as num).toDouble();
        if (speed < 0 || speed > 10) continue;

        final roundedMinute = timestamp.minute - (timestamp.minute % 5);
        final slotTime = DateTime(
          timestamp.year,
          timestamp.month,
          timestamp.day,
          timestamp.hour,
          roundedMinute,
        );
        final key = slotTime.toIso8601String();
        grouped.putIfAbsent(key, () => []).add(speed);
      }

      final List<HourlySpeed> results = [];
      for (final entry in grouped.entries) {
        final time = DateTime.parse(entry.key);
        final avgSpeed =
            entry.value.reduce((a, b) => a + b) / entry.value.length;
        results.add(HourlySpeed(time: time, averageSpeed: avgSpeed));
      }

      results.sort((a, b) => a.time.compareTo(b.time));
      return results;
    } catch (e) {
      debugPrint('❌ fetchTodaySpeedData 오류: $e');
      return [];
    }
  }

  static String _dateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}
