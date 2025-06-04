// analytics_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';

import 'package:walk_guide/session_detail_page.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/services/firestore_service.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  List<HourlySpeed> todaySpeedChart = [];
  Map<String, double> weeklyAverageSpeed = {};
  Map<String, int> weeklyStepCounts = {};
  List<String> dates = [];

  @override
  void initState() {
    super.initState();
    loadTodaySpeedChart();
    loadWeeklySummaries();
  }

  Future<void> loadTodaySpeedChart() async {
    final result = await FirestoreService.fetchTodaySpeedData();
    setState(() {
      todaySpeedChart = result;
    });
  }

  Future<void> loadWeeklySummaries() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));

    final Map<String, List<double>> speedGrouped = {};
    final Map<String, int> stepsGrouped = {};

    for (final session in sessions) {
      if (session.startTime.isBefore(sevenDaysAgo)) continue;
      final key = getDateKey(session.startTime);
      speedGrouped.putIfAbsent(key, () => []);
      speedGrouped[key]!.add(session.averageSpeed);

      stepsGrouped.update(key, (v) => v + session.stepCount,
          ifAbsent: () => session.stepCount);
    }

    final resultSpeed = <String, double>{};
    for (var entry in speedGrouped.entries) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      resultSpeed[entry.key] = double.parse(avg.toStringAsFixed(2));
    }

    setState(() {
      weeklyAverageSpeed = resultSpeed;
      weeklyStepCounts = stepsGrouped;
      dates = resultSpeed.keys.toList();
    });
  }

  String getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> clearAllSessions() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    await box.clear();
    setState(() {
      todaySpeedChart.clear();
    });
  }

  Future<void> backupSessionsToJson() async {
    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    final jsonString = jsonEncode(sessions.map((s) => s.toJson()).toList());

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walk_sessions_backup.json');
    await file.writeAsString(jsonString);
  }

  Future<void> restoreSessionsFromJson() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walk_sessions_backup.json');
      if (!await file.exists()) return;

      final jsonString = await file.readAsString();
      final jsonList = jsonDecode(jsonString);
      final restored = (jsonList as List)
          .map((json) => WalkSession(
                startTime: DateTime.parse(json['startTime']),
                endTime: DateTime.parse(json['endTime']),
                stepCount: json['stepCount'],
                averageSpeed: (json['averageSpeed'] as num).toDouble(),
              ))
          .toList();

      final box = Hive.box<WalkSession>('walk_sessions');
      await box.clear();
      await box.addAll(restored);
    } catch (e) {
      debugPrint('❌ 복원 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true, // 가운데 정렬
        backgroundColor: Colors.amber,
        title: const Text(
          '보행 데이터 분석',
          style: TextStyle(
            fontFamily: 'Gugi', // 궁서체 느낌의 폰트
            fontWeight: FontWeight.bold, // 두껍게
            fontSize: 22, // 보기 좋게 크기 조절
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('오늘 하루 속도 변화',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 24,
                  minY: 0,
                  maxY: 2,
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 2,
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipRoundedRadius: 6,
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '${spot.y.toStringAsFixed(2)} m/s',
                            const TextStyle(
                              color: Colors.white,
                              backgroundColor: Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: todaySpeedChart.map((e) {
                        final x = e.time.hour + (e.time.minute / 60.0);
                        return FlSpot(x, e.averageSpeed);
                      }).toList(),
                      isCurved: false,
                      color: const Color.fromARGB(255, 161, 222, 255),
                      barWidth: 4, // 선 두께 증가
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.lightBlueAccent,
                            strokeWidth: 1,
                            strokeColor: Colors.blueGrey,
                          );
                        },
                      ),
                    ),
                  ],
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
                  barGroups: List.generate(dates.length, (i) {
                    final date = dates[i];
                    final speed = weeklyAverageSpeed[date]!;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                            toY: speed, width: 12, color: Colors.green)
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i < 0 || i >= dates.length)
                            return const SizedBox();
                          return Text(dates[i].substring(5),
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('최근 일주일 걸음 수 변화',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(dates.length, (i) {
                    final date = dates[i];
                    final steps = weeklyStepCounts[date]?.toDouble() ?? 0;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                            toY: steps, width: 12, color: Colors.deepOrange)
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i < 0 || i >= dates.length)
                            return const SizedBox();
                          return Text(dates[i].substring(5),
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
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
                      final s = sessions[index];
                      return ListTile(
                        title: Text(getDateKey(s.startTime)),
                        subtitle: Text(
                            '걸음 수: ${s.stepCount}, 평균 속도: ${s.averageSpeed.toStringAsFixed(2)} m/s'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SessionDetailPage(session: s),
                            ),
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
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🗑️ 모든 세션이 삭제되었습니다')));
                  },
                  child: const Text('초기화'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await backupSessionsToJson();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ JSON으로 백업됨')));
                  },
                  child: const Text('백업'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await restoreSessionsFromJson();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('✅ 복원 완료')));
                    setState(() {});
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
