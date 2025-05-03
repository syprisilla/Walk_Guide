import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  final double Function()? onGetSpeed;

  const AnalyticsDashboardPage({super.key, this.onGetSpeed});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  List<double> speedData = [];
  Timer? _speedTimer;

  @override
  void initState() {
    super.initState();

    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      double currentSpeed = getRealTimeSpeed();
      setState(() {
        speedData.add(currentSpeed);
        if (speedData.length > 30) {
          speedData.removeAt(0);
        }
      });
    });
  }

  double getRealTimeSpeed() {
    return 1.2 + (speedData.length % 5) * 0.2;
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
            const SizedBox(
                height: 120, child: Center(child: Text('📅 여기에 그래프 표시'))),
            const SizedBox(height: 16),
            const Text(
              '세션 다시보기',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 80, child: Center(child: Text('🔁 세션 리스트'))),
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
