import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'package:walk_guide/walk_session.dart';

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

  @override
  void dispose() {
    _speedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            const Text(
              '실시간 속도 그래프',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
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
                        spots: List.generate(
                          speedData.length,
                          (i) => FlSpot(i.toDouble(), speedData[i]),
                        ),
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
            const Text(
              '최근 일주일 평균 속도 변화',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              height: 120,
              child: weeklyAverages.isEmpty
                  ? const Center(child: Text('📅 데이터 없음'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final keyList = weeklyAverages.keys.toList();
                                final index = value.toInt();
                                if (index < 0 || index >= keyList.length)
                                  return const SizedBox.shrink();
                                final label =
                                    keyList[index].substring(5); // MM-DD
                                return Text(label,
                                    style: const TextStyle(fontSize: 10));
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(weeklyAverages.length, (i) {
                          final key = weeklyAverages.keys.toList()[i];
                          final value = weeklyAverages[key] ?? 0;
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                  toY: value, width: 12, color: Colors.orange),
                            ],
                          );
                        }),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            const Text(
              '세션 다시보기',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(
              height: 80,
              child: Center(child: Text('🔁 세션 리스트')),
            ),
            const SizedBox(height: 16),
            const Text(
              '데이터 초기화 및 백업',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                ElevatedButton(onPressed: null, child: const Text('초기화')),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: null, child: const Text('백업')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
