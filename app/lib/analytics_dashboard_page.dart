import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:walk_guide/real_time_speed_service.dart';
import 'package:walk_guide/session_detail_page.dart';
import 'package:walk_guide/walk_session.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  List<double> speedData = [];
  Map<String, double> weeklyAverages = {};
  Timer? _speedTimer;

  @override
  void initState() {
    super.initState();
    _startSpeedTracking();
    loadWeeklyAverages();
  }

  void _startSpeedTracking() {
    _speedTimer?.cancel();

    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final box = Hive.box<DateTime>('recent_steps');
      final now = DateTime.now();

      // Hive에 저장된 전체 recent_steps 로그 수 출력
      debugPrint("📦 Hive recent_steps 전체: ${box.length}");

      // 유효한 걸음만 필터링 (5초 이내)
      final validSteps =
          box.values.where((t) => now.difference(t).inSeconds <= 5).toList();

      for (final stepTime in box.values) {
        final diff = now.difference(stepTime).inSeconds;
        debugPrint("⏱️ 기록된 시간: $stepTime, 차이: ${diff}초");
      }

      final double speed = validSteps.length * 0.7 / 5;
      debugPrint("📈 계산된 실시간 속도 (Hive 기반): $speed");

      // speed가 0이더라도 항상 setState 호출
      setState(() {
        speedData.add(speed);
        if (speedData.length > 30) speedData.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    super.dispose();
  }

  Future<void> loadWeeklyAverages() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    final allSessions = box.values.toList();
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));

    final Map<String, List<double>> grouped = {};
    for (final session in allSessions) {
      if (session.startTime.isBefore(sevenDaysAgo)) continue;
      final dateKey = getDateKey(session.startTime);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(session.averageSpeed);
    }

    final Map<String, double> result = {};
    for (final entry in grouped.entries) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      result[entry.key] = double.parse(avg.toStringAsFixed(2));
    }

    setState(() {
      weeklyAverages = result;
    });
  }

  String getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> clearAllSessions() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    await box.clear();
    setState(() {
      speedData.clear();
    });
  }

  Future<void> backupSessionsToJson() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    final jsonList = sessions.map((s) => s.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/walk_sessions_backup.json');
    await file.writeAsString(jsonString);
    debugPrint('✅ 백업 완료: ${file.path}');
  }

  Future<void> restoreSessionsFromJson() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/walk_sessions_backup.json');

      if (!await file.exists()) {
        debugPrint('⚠️ 백업 파일이 존재하지 않습니다');
        return;
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);

      final restoredSessions = jsonList.map((json) => WalkSession(
            startTime: DateTime.parse(json['startTime']),
            endTime: DateTime.parse(json['endTime']),
            stepCount: json['stepCount'],
            averageSpeed: (json['averageSpeed'] as num).toDouble(),
          ));

      final box = Hive.box<WalkSession>('walk_sessions');
      await box.clear();
      await box.addAll(restoredSessions);

      debugPrint('✅ 복원 완료: ${restoredSessions.length}개의 세션 복구됨');
    } catch (e) {
      debugPrint('❌ 복원 중 오류 발생: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = weeklyAverages.keys.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 보행 데이터 분석'),
        backgroundColor: Colors.amber,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('실시간 속도 그래프',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 120,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: LineChart(
                  LineChartData(
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(speedData.length,
                            (i) => FlSpot(i.toDouble(), speedData[i])),
                        isCurved: true,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('최근 일주일 평균 속도 변화',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (group.x.toInt() >= dates.length) return null;
                        final date = dates[group.x.toInt()];
                        final speed = rod.toY.toStringAsFixed(2);
                        return BarTooltipItem('$date\n속도: $speed m/s',
                            const TextStyle(color: Colors.white, fontSize: 14));
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= dates.length) {
                            return const SizedBox();
                          }
                          final date = dates[index];
                          return Text(date.substring(5),
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(dates.length, (index) {
                    final date = dates[index];
                    final speed = weeklyAverages[date]!;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                            toY: speed, width: 12, color: Colors.teal)
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('세션 다시보기',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 200,
              child: ValueListenableBuilder(
                valueListenable:
                    Hive.box<WalkSession>('walk_sessions').listenable(),
                builder: (context, Box<WalkSession> box, _) {
                  if (box.isEmpty) {
                    return const Center(child: Text('저장된 세션이 없습니다.'));
                  }
                  final sessions = box.values.toList().reversed.toList();
                  return ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final date = getDateKey(session.startTime);
                      return ListTile(
                        title: Text(date),
                        subtitle: Text(
                            '걸음 수: ${session.stepCount} / 평균 속도: ${session.averageSpeed.toStringAsFixed(2)} m/s'),
                        leading: const Icon(Icons.directions_walk),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    SessionDetailPage(session: session)),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('데이터 초기화 및 백업',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await clearAllSessions();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🗑️ 모든 세션이 삭제되었습니다')),
                      );
                    }
                  },
                  child: const Text('초기화'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await backupSessionsToJson();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ 데이터가 JSON으로 백업되었습니다')),
                      );
                    }
                  },
                  child: const Text('백업'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await restoreSessionsFromJson();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ 백업 데이터에서 세션을 복원했습니다')),
                      );
                      setState(() {});
                    }
                  },
                  child: const Text('복원'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension WalkSessionJson on WalkSession {
  Map<String, dynamic> toJson() => {
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'stepCount': stepCount,
        'averageSpeed': averageSpeed,
      };
}
