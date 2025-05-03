import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/session_detail_page.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  final double Function()? onGetSpeed;

  const AnalyticsDashboardPage({super.key, this.onGetSpeed});

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
    speedData.clear();
    speedData.add(0);
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      double currentSpeed = widget.onGetSpeed?.call() ?? 0;
      setState(() {
        speedData.add(currentSpeed);
        if (speedData.length > 30) speedData.removeAt(0);
      });
    });
    loadWeeklyAverages();
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
    setState(() {});
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
                    leftTitles: AxisTitles(),
                    rightTitles: AxisTitles(),
                    topTitles: AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= dates.length)
                            return const SizedBox();
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
                            toY: speed, width: 12, color: Colors.teal),
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
                    onPressed: clearAllSessions, child: const Text('초기화')),
                const SizedBox(width: 10),
                ElevatedButton(
                    onPressed: backupSessionsToJson, child: const Text('백업')),
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
