import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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

  int _steps = 0;
  int? _initialSteps;
  int? _previousSteps;
  DateTime? _startTime;
  DateTime? _lastMovementTime;

  bool _isMoving = false;
  List<DateTime> _recentSteps = [];

  static const double movementThreshold = 1.5;

  @override
  void initState() {
    super.initState();
    requestPermission();
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
          builder:
              (_) => AlertDialog(
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
        }
      }
    });
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

  void startCheckingMovement() {
    _checkTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_lastMovementTime != null) {
        final diff =
            DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        if (diff >= 1500 && _isMoving) {
          setState(() {
            _isMoving = false;
            _steps = 0;
            _initialSteps = null;
            _previousSteps = null;
            _startTime = null;
            _recentSteps.clear();
          });
          debugPrint("정지 감지 → 걸음 수 초기화!");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('걸음 속도 측정')),
      body: Stack(
        children: [
          // 📷 카메라 자리 (지금은 회색 배경)
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

          // 📊 정보 박스
          Positioned(
            top: 30,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _isMoving ? '움직이는 중' : '정지 상태',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '걸음 수: $_steps',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '평균 속도: ${getAverageSpeed().toStringAsFixed(2)} m/s',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '3초 속도: ${getRealTimeSpeed().toStringAsFixed(2)} m/s',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ],
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
