import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'dart:io';

import 'package:walk_guide/session_detail_page.dart';
import 'package:walk_guide/walk_session.dart';
import 'package:walk_guide/services/firestore_service.dart';
import 'package:walk_guide/voice_guide_service.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  final FlutterTts _flutterTts = FlutterTts();
  List<HourlySpeed> todaySpeedChart = [];
  Map<String, double> weeklyAverageSpeed = {};
  Map<String, int> weeklyStepCounts = {};
  List<String> dates = [];

  @override
  void initState() {
    super.initState();
    _flutterTts.awaitSpeakCompletion(true);
    loadData();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> loadData() async {
    await loadTodaySpeedChart();
    await loadWeeklySummaries();
    await _speakSummary();
  }

  Future<void> _speakSummary() async {
    final enabled = await isNavigationVoiceEnabled();
    if (!enabled) return;

    if (todaySpeedChart.isEmpty || weeklyAverageSpeed.isEmpty) return;

    final todayAvgSpeed =
        todaySpeedChart.map((e) => e.averageSpeed).reduce((a, b) => a + b) /
            todaySpeedChart.length;
    final weeklyAvg = weeklyAverageSpeed.values.reduce((a, b) => a + b) /
        weeklyAverageSpeed.length;
    final diff = todayAvgSpeed - weeklyAvg;
    final speedCompare = diff.abs() < 0.1
        ? '오늘은 평소와 비슷한 속도로 걸으셨어요.'
        : (diff > 0 ? '오늘은 평소보다 빠르게 걸으셨어요.' : '오늘은 평소보다 느리게 걸으셨어요.');

    final todayKey = getDateKey(DateTime.now());
    final steps = weeklyStepCounts[todayKey] ?? 0;
    final stepMsg = '오늘은 총 $steps 걸음을 걸으셨어요.';

    final message = '$speedCompare $stepMsg';

    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);
  }

  Future<void> _speak(String message) async {
    final enabled = await isNavigationVoiceEnabled();
    if (!enabled) return;
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);
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

  Future<void> clearAllFirestoreSpeedData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('walking_data');

    final snapshot = await collection.get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
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

      // Firestore에도 복원
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final collection = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('walking_data');

// 기존 Firestore 데이터 삭제
      final snapshot = await collection.get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

//  복원된 데이터 Firestore에 Timestamp로 저장
      for (final session in restored) {
        final timestamp = session.startTime.toIso8601String();
        await collection.doc(timestamp).set({
          'timestamp': Timestamp.fromDate(session.startTime),
          'speed': session.averageSpeed,
        });
      }
    } catch (e) {
      debugPrint('❌ 복원 오류: $e');
    }
  }

  Future<void> onClearPressed() async {
    await clearAllSessions();
    await clearAllFirestoreSpeedData();
    await loadTodaySpeedChart();
    await loadWeeklySummaries();
    await _speak("모든 데이터를 초기화했습니다.");
  }

  Future<void> onBackupPressed() async {
    await backupSessionsToJson();
    await _speak("백업 버튼을 눌렀습니다.");
  }

  Future<void> onRestorePressed() async {
    await restoreSessionsFromJson();
    await loadWeeklySummaries();
    await loadTodaySpeedChart();
    await _speak("복원 버튼을 눌렀습니다.");
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
              width: double.infinity,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(dates.length, (i) {
                    final date = dates[i];
                    final speed = weeklyAverageSpeed[date]!;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: speed,
                          width: 30,
                          borderRadius: BorderRadius.circular(4),
                          rodStackItems: [
                            BarChartRodStackItem(0, 2, Colors.grey.shade200),
                          ],
                          color: speed > 0
                              ? Colors.blueAccent
                              : Colors.transparent,
                        )
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
                          return Text(
                            dates[i].substring(5),
                            style: const TextStyle(
                              fontSize: 14, //  글자 크기 키움
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1.0,
                        getTitlesWidget: (value, _) => Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: true),
                  maxY: 2,
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
                    await clearAllSessions(); // Hive 데이터 삭제
                    await clearAllFirestoreSpeedData(); // Firestore 속도 삭제
                    await loadTodaySpeedChart(); // 그래프 갱신
                    await loadWeeklySummaries();
                    await _speak("모든 데이터를 초기화했습니다.");
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('모든 데이터가 초기화되었습니다')),
                    );
                  },
                  child: const Text('초기화'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await backupSessionsToJson();
                    await _speak("백업 버튼을 눌렀습니다.");
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON으로 백업됨')),
                    );
                  },
                  child: const Text('백업'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    await restoreSessionsFromJson();
                    await loadWeeklySummaries(); // 세션 다시 불러오기
                    await loadTodaySpeedChart(); // 그래프 갱신 추가
                    await _speak("복원 버튼을 눌렀습니다.");
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(' 복원 완료')),
                    );
                    setState(() {}); // 위 두 개가 있더라도 이건 재렌더링을 위해 유지
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
