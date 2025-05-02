import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'walk_session.dart';

class StepCounterPage extends StatefulWidget {
  const StepCounterPage({super.key});

  @override
  State<StepCounterPage> createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> {
  late Stream<StepCount> _stepCountStream;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _checkTimer;
  late FlutterTts flutterTts;

  int _steps = 0;
  int? _initialSteps;
  int? _previousSteps;
  DateTime? _startTime;
  DateTime? _lastMovementTime;
  DateTime? _lastGuidanceTime;

  bool _isMoving = false;
  List<DateTime> _recentSteps = [];

  List<WalkSession> _sessionHistory = [];

  static const double movementThreshold = 1.5;

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5);
    requestPermission();
    loadSessions();
  }

  Future<void> requestPermission() async {
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
    }

    if (status.isGranted) {
      startPedometer();
      startAccelerometer();
      startCheckingMovement();
    } else {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('권한 필요'),
            content: const Text('걸음 측정을 위해 권한을 허용해 주세요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  void startPedometer() {
    _stepCountSubscription?.cancel();
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountSubscription = _stepCountStream.listen(
      onStepCount,
      onError: onStepCountError,
      cancelOnError: true,
    );
  }

  void startAccelerometer() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      double totalAcceleration = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      double movement = (totalAcceleration - 9.8).abs();

      if (movement > movementThreshold) {
        _lastMovementTime = DateTime.now();
        if (!_isMoving) {
          setState(() {
            _isMoving = true;
          });
          debugPrint("움직임 감지!");

          onObjectDetected();
        }
      }
    });
  }

  Duration getGuidanceDelay(double avgSpeed) {
    if (avgSpeed < 0.5) {
      return const Duration(seconds: 2);
    } else if (avgSpeed < 1.2) {
      return const Duration(milliseconds: 1500);
    } else {
      return const Duration(seconds: 1);
    }
  }

  void onObjectDetected() {
    guideWhenObjectDetected();
  }

  void guideWhenObjectDetected() async {
    final now = DateTime.now();

    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!).inSeconds < 2) {
      debugPrint("⏳ 쿨다운 중 - 음성 안내 생략");
      return;
    }

    double avgSpeed = getRealTimeSpeed();
    final delay = getGuidanceDelay(avgSpeed);

    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정...");
    await Future.delayed(delay);

    await flutterTts.speak("앞에 장애물이 있습니다. 조심하세요.");
    debugPrint("🔊 안내 완료: 앞에 장애물이 있습니다.");
  }

  void onStepCount(StepCount event) {
    debugPrint("걸음 수 이벤트 발생: ${event.steps}");

    if (_initialSteps == null) {
      _initialSteps = event.steps;
      _previousSteps = event.steps;
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now();
      _recentSteps.clear();
      setState(() {});
      return;
    }

    setState(() {
      int stepDelta = event.steps - (_previousSteps ?? event.steps);
      if (stepDelta > 0) {
        _steps += stepDelta;
        for (int i = 0; i < stepDelta; i++) {
          _recentSteps.add(DateTime.now());
        }
      }
      _previousSteps = event.steps;
      _lastMovementTime = DateTime.now();
    });
  }

  void onStepCountError(error) {
    debugPrint('걸음 수 측정 오류: $error');
    Future.delayed(const Duration(seconds: 2), () {
      debugPrint('걸음 측정 재시도');
      startPedometer();
    });
  }

  double getAverageSpeed() {
    if (_startTime == null || _steps == 0) return 0;
    final duration = DateTime.now().difference(_startTime!).inSeconds;
    if (duration == 0) return 0;
    double stepLength = 0.7;
    double distance = _steps * stepLength;
    return distance / duration;
  }

  double getRealTimeSpeed() {
    if (_recentSteps.isEmpty) return 0;
    DateTime now = DateTime.now();
    _recentSteps =
        _recentSteps.where((t) => now.difference(t).inSeconds <= 3).toList();
    int stepsInLast3Seconds = _recentSteps.length;
    double stepLength = 0.7;
    double distance = stepsInLast3Seconds * stepLength;
    return distance / 3;
  }

  void _saveSessionData() {
    if (_startTime == null || _steps == 0) return;

    final endTime = DateTime.now();
    final session = WalkSession(
      startTime: _startTime!,
      endTime: endTime,
      stepCount: _steps,
      averageSpeed: getAverageSpeed(),
    );

    _sessionHistory.add(session);

    final box = Hive.box<WalkSession>('walk_sessions');
    box.add(session);

    debugPrint("🟢 저장된 세션: $session");
    debugPrint("💾 Hive에 저장된 세션 수: ${box.length}");

    analyzeWalkingPattern();

    _steps = 0;
    _initialSteps = null;
    _previousSteps = null;
    _startTime = null;
    _recentSteps.clear();
  }

  void startCheckingMovement() {
    _checkTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_lastMovementTime != null) {
        final diff =
            DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        if (diff >= 1500 && _isMoving) {
          _saveSessionData();
          setState(() {
            _isMoving = false;
          });
          debugPrint("정지 감지 → 걸음 수 초기화!");
        }
      }
    });
  }

  void loadSessions() {
    final box = Hive.box<WalkSession>('walk_sessions');
    setState(() {
      _sessionHistory = box.values.toList();
    });
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");

    analyzeWalkingPattern();
  }

  void analyzeWalkingPattern() {
    if (_sessionHistory.isEmpty) {
      debugPrint("⚠️ 보행 데이터가 없습니다.");
      return;
    }

    double totalSpeed = 0;
    int totalSteps = 0;
    int totalDuration = 0;

    for (var session in _sessionHistory) {
      totalSpeed += session.averageSpeed;
      totalSteps += session.stepCount;
      totalDuration += session.endTime.difference(session.startTime).inSeconds;
    }

    double avgSpeed = totalSpeed / _sessionHistory.length;
    double avgSteps = totalSteps / _sessionHistory.length;
    double avgDuration = totalDuration / _sessionHistory.length;

    debugPrint("📊 보행 패턴 분석 결과:");
    debugPrint("- 평균 속도: ${avgSpeed.toStringAsFixed(2)} m/s");
    debugPrint("- 평균 걸음 수: ${avgSteps.toStringAsFixed(1)} 걸음");
    debugPrint("- 평균 세션 시간: ${avgDuration.toStringAsFixed(1)} 초");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('걸음 속도 측정')),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Text(
              '카메라 영역',
              style: TextStyle(fontSize: 24, color: Colors.black38),
            ),
          ),
          Positioned(
            top: 30,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _isMoving ? '움직이는 중' : '정지 상태',
                  style: const TextStyle(fontSize: 18, color: Colors.black),
                ),
                const SizedBox(height: 10),
                Text(
                  '걸음 수: $_steps',
                  style: const TextStyle(fontSize: 18, color: Colors.black),
                ),
                const SizedBox(height: 5),
                Text(
                  '평균 속도: ${getAverageSpeed().toStringAsFixed(2)} m/s',
                  style: const TextStyle(fontSize: 18, color: Colors.black),
                ),
                const SizedBox(height: 5),
                Text(
                  '3초 속도: ${getRealTimeSpeed().toStringAsFixed(2)} m/s',
                  style: const TextStyle(fontSize: 18, color: Colors.black),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              height: 180,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.builder(
                itemCount: _sessionHistory.length,
                itemBuilder: (context, index) {
                  final session = _sessionHistory[index];
                  return Text(
                    '${index + 1}) ${session.stepCount}걸음, 평균속도: ${session.averageSpeed.toStringAsFixed(2)} m/s',
                    style: const TextStyle(fontSize: 16),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }
}
