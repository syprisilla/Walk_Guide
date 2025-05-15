import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import 'walk_session.dart';

import './ObjectDetection/object_detection_view.dart';

class StepCounterPage extends StatefulWidget {
  final void Function(double Function())? onInitialized;
  final List<CameraDescription> cameras;

  const StepCounterPage({
    super.key,
    this.onInitialized,
    required this.cameras,
  });

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
    widget.onInitialized?.call(getRealTimeSpeed);
  }

  void _handleDetectedObjects(List<DetectedObject> objects) {
    if (!mounted) return;
    if (objects.isNotEmpty) {
      guideWhenObjectDetected();
    }
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
          if (mounted) {
            setState(() {
              _isMoving = true;
            });
          }
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
      return;
    }
    double avgSpeed = getRealTimeSpeed();
    final delay = getGuidanceDelay(avgSpeed);
    await Future.delayed(delay);
    await flutterTts.speak("앞에 장애물이 있습니다. 조심하세요.");
    _lastGuidanceTime = DateTime.now();
  }

  void onStepCount(StepCount event) {
    if (_initialSteps == null) {
      _initialSteps = event.steps;
      _previousSteps = event.steps;
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now();
      _recentSteps.clear();
      if (mounted) setState(() {});
      return;
    }
    if (mounted) {
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
  }

  void onStepCountError(error) {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) startPedometer();
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
    analyzeWalkingPattern();
    _steps = 0;
    _initialSteps = null;
    _previousSteps = null;
    _startTime = null;
    _recentSteps.clear();
  }

  void startCheckingMovement() {
    _checkTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lastMovementTime != null) {
        final diff =
            DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        if (diff >= 1500 && _isMoving) {
          _saveSessionData();
          if (mounted) {
            setState(() {
              _isMoving = false;
            });
          }
        }
      }
    });
  }

  void loadSessions() {
    final box = Hive.box<WalkSession>('walk_sessions');
    if (mounted) {
      setState(() {
        _sessionHistory = box.values.toList();
      });
    }
    analyzeWalkingPattern();
  }

  void analyzeWalkingPattern() {
    if (_sessionHistory.isEmpty) {
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
    if (_sessionHistory.isNotEmpty) {
      double avgSpeed = totalSpeed / _sessionHistory.length;
      double avgSteps = totalSteps / _sessionHistory.length;
      double avgDuration = totalDuration / _sessionHistory.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('보행 중')),
      body: Stack(
        children: [
          Positioned.fill(
            child: (widget.cameras.isNotEmpty)
                ? ObjectDetectionView(
                    cameras: widget.cameras,
                    onObjectsDetected: _handleDetectedObjects,
                  )
                : Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: const Text(
                      '카메라를 사용할 수 없습니다.\n앱 권한을 확인해주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.redAccent),
                    ),
                  ),
          ),
          Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _isMoving ? '보행 중' : '정지 상태',
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_steps 걸음',
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('평균 속도',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(
                              '${getAverageSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.lightGreenAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text('실시간 속도',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(
                              '${getRealTimeSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Opacity(
              opacity: 0.85,
              child: Container(
                height: 150,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black26)),
                // _sessionHistory가 비어있으면 ListView.builder 대신 빈 Container를 반환하여 아무것도 표시하지 않음
                child: _sessionHistory.isEmpty
                    ? Container() // 기록이 없으면 아무것도 표시하지 않음
                    : ListView.builder(
                        itemCount: _sessionHistory.length,
                        itemBuilder: (context, index) {
                          final session = _sessionHistory[
                              _sessionHistory.length - 1 - index];
                          return Card(
                            color: Colors.grey[700],
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                '${_sessionHistory.length - index}) ${session.stepCount}걸음, 평균 ${session.averageSpeed.toStringAsFixed(2)} m/s (${(session.endTime.difference(session.startTime).inSeconds / 60).toStringAsFixed(1)}분)',
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
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
    flutterTts.stop();
    super.dispose();
  }
}
