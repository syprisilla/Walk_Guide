import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:camera/camera.dart';

import 'walk_session.dart';
import 'package:walk_guide/real_time_speed_service.dart';
import 'package:walk_guide/voice_guide_service.dart';

import './ObjectDetection/object_detection_view.dart'; // DetectedObjectInfo 포함

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
  List<WalkSession> _sessionHistory = [];

  static const double movementThreshold = 1.5;

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5);
    flutterTts.setLanguage("ko-KR");
    requestPermission();
    loadSessions();
    widget.onInitialized?.call(() => RealTimeSpeedService.getSpeed());
  }

  void _handleDetectedObjects(List<DetectedObjectInfo> objectsInfo) {
    if (!mounted || _isDisposed) return; // _isDisposed 확인 추가 (만약을 위해)
    if (objectsInfo.isNotEmpty) {
      final DetectedObjectInfo firstObjectInfo = objectsInfo.first;
      guideWhenObjectDetected(firstObjectInfo);
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
      if (context.mounted && !_isDisposed) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('권한 필요'),
            content: const Text('걸음 측정을 위해 활동 인식 권한을 허용해 주세요.'),
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
    if (_isDisposed) return;
    _stepCountSubscription?.cancel();
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountSubscription = _stepCountStream.listen(
      onStepCount,
      onError: onStepCountError,
      cancelOnError: true,
    );
  }

  void startAccelerometer() {
    if (_isDisposed) return;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      if (_isDisposed) return;
      double totalAcceleration =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      double movement = (totalAcceleration - 9.8).abs();

      if (movement > movementThreshold) {
        _lastMovementTime = DateTime.now();
        if (!_isMoving) {
          if (mounted && !_isDisposed) {
            setState(() {
              _isMoving = true;
            });
          }
          debugPrint("움직임 감지!");
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

  // TTS 메시지 단순화
  void guideWhenObjectDetected(DetectedObjectInfo objectInfo) async {
    if (_isDisposed) return;
    final now = DateTime.now();
    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!).inSeconds < 3) {
      debugPrint("⏳ 쿨다운 중 - 음성 안내 생략 (마지막 안내: $_lastGuidanceTime)");
      return;
    }

    bool voiceEnabled = await isVoiceGuideEnabled();
    if (!voiceEnabled) {
      debugPrint("🔇 음성 안내 비활성화됨 - 안내 생략");
      return;
    }

    double avgSpeed = RealTimeSpeedService.getSpeed();
    final delay = getGuidanceDelay(avgSpeed);

    // String objectLabel = objectInfo.label ?? "장애물"; // 객체 종류(label)는 더 이상 사용 안 함
    String sizeDesc = objectInfo.sizeDescription;
    String message = "전방에";
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc 크기의"; // "크기의" 추가하여 자연스럽게
    }
    message += " 장애물이 있습니다. 주의하세요."; // "장애물"로 고정
    
    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정... TTS 메시지: $message");
    
    // TTS 호출 전에 Future.delayed가 완료될 때까지 기다린 후,
    // 다시 한번 _isDisposed를 체크하여 안전하게 speak 호출
    await Future.delayed(delay);
    if (_isDisposed) return; 

    await flutterTts.speak(message);
    debugPrint("🔊 안내 완료: $message");
    _lastGuidanceTime = DateTime.now();
  }

  void onStepCount(StepCount event) async {
    if (!mounted || _isDisposed) return;

    debugPrint("걸음 수 이벤트 발생: ${event.steps}");

    if (_initialSteps == null) {
      _initialSteps = event.steps;
      _previousSteps = event.steps;
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now();
      RealTimeSpeedService.clear();
      if (mounted && !_isDisposed) setState(() {});
      return;
    }

    int stepDelta = event.steps - (_previousSteps ?? event.steps);
    if (stepDelta > 0) {
      _steps += stepDelta;
      final now = DateTime.now();
      for (int i = 0; i < stepDelta; i++) {
        RealTimeSpeedService.recordStep(now);
        // Hive.box<DateTime>('recent_steps').add(now); // 필요시 주석 해제
      }
    }
    _previousSteps = event.steps;
    _lastMovementTime = DateTime.now();

    if (mounted && !_isDisposed) {
      setState(() {});
    }
  }

  void onStepCountError(error) {
    if (_isDisposed) return;
    debugPrint('걸음 수 측정 오류: $error');
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_isDisposed) {
        debugPrint('걸음 측정 재시도...');
        startPedometer();
      }
    });
  }

  double getAverageSpeed() {
    if (_startTime == null || _steps == 0) return 0;
    final durationInSeconds = DateTime.now().difference(_startTime!).inSeconds;
    if (durationInSeconds == 0) return 0;
    double stepLength = 0.7;
    double distanceInMeters = _steps * stepLength;
    return distanceInMeters / durationInSeconds;
  }

  double getRealTimeSpeed() {
    return RealTimeSpeedService.getSpeed();
  }

  void _saveSessionData() {
    if (_isDisposed) return;
    if (_startTime == null || _steps == 0) {
      debugPrint("세션 저장 스킵: 시작 시간이 없거나 걸음 수가 0입니다.");
      _steps = 0;
      _initialSteps = null;
      _previousSteps = null;
      _startTime = null;
      RealTimeSpeedService.clear();
      if (mounted && !_isDisposed) setState(() {});
      return;
    }

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
    RealTimeSpeedService.clear();
    if (mounted && !_isDisposed) setState((){});
  }

  void startCheckingMovement() {
    if (_isDisposed) return;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isDisposed) { // _isDisposed 확인 추가
        timer.cancel();
        return;
      }
      if (_lastMovementTime != null && _isMoving) {
        final diff = DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        if (diff >= 2000) {
          if (mounted && !_isDisposed) {
            setState(() {
              _isMoving = false;
            });
          }
          debugPrint("정지 감지 (2초 이상 움직임 없음)!");
          _saveSessionData();
        }
      } else if (_lastMovementTime == null && _isMoving) {
        if (mounted && !_isDisposed) {
            setState(() {
                _isMoving = false;
            });
        }
      }
    });
  }

  void loadSessions() {
    if (_isDisposed) return;
    final box = Hive.box<WalkSession>('walk_sessions');
    final loadedSessions = box.values.toList();
    if (mounted && !_isDisposed) {
      setState(() {
        _sessionHistory = loadedSessions.reversed.toList();
      });
    } else if (!_isDisposed) { // mounted되지 않았지만 dispose되지도 않은 경우
      _sessionHistory = loadedSessions.reversed.toList();
    }
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");
    analyzeWalkingPattern();
  }

  void analyzeWalkingPattern() {
    if (_isDisposed || _sessionHistory.isEmpty) { // _isDisposed 확인 추가
      debugPrint("⚠️ 보행 데이터가 없어 패턴 분석을 건너뜁니다.");
      return;
    }

    double totalSpeed = 0;
    int totalSteps = 0;
    int totalDurationSeconds = 0;

    for (var session in _sessionHistory) {
      totalSpeed += session.averageSpeed;
      totalSteps += session.stepCount;
      totalDurationSeconds += session.endTime.difference(session.startTime).inSeconds;
    }

    int sessionCount = _sessionHistory.length;
    double overallAvgSpeed = sessionCount > 0 ? totalSpeed / sessionCount : 0;
    double avgStepsPerSession = sessionCount > 0 ? totalSteps / sessionCount : 0;
    double avgDurationPerSessionSeconds = sessionCount > 0 ? totalDurationSeconds / sessionCount : 0;

    debugPrint("📊 보행 패턴 분석 결과:");
    debugPrint("- 전체 평균 속도: ${overallAvgSpeed.toStringAsFixed(2)} m/s");
    debugPrint("- 세션 당 평균 걸음 수: ${avgStepsPerSession.toStringAsFixed(1)} 걸음");
    debugPrint("- 세션 당 평균 시간: ${(avgDurationPerSessionSeconds / 60).toStringAsFixed(1)} 분 (${avgDurationPerSessionSeconds.toStringAsFixed(1)} 초)");
  }

  // dispose 상태를 나타내는 플래그
  bool _isDisposed = false;

  @override
  Widget build(BuildContext context) {
    // ... (build 메서드 내 UI 코드는 이전 답변의 최종본과 거의 동일하게 유지) ...
    // ObjectDetectionView의 onObjectsDetected 콜백은 _handleDetectedObjects로 연결
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
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _isMoving ? '🚶 보행 중' : '🛑 정지 상태',
                              style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_steps 걸음',
                              style: const TextStyle(
                                  fontSize: 20,
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 50, width: 1, color: Colors.white30, margin: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('평균 속도',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.white70)),
                            const SizedBox(height: 2),
                            Text(
                              '${getAverageSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.lightGreenAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text('실시간 속도',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.white70)),
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
          if (_sessionHistory.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Opacity(
                opacity: 0.9,
                child: Container(
                  height: 160,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.blueGrey[800],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black38)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "최근 보행 기록",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _sessionHistory.length > 5 ? 5 : _sessionHistory.length,
                          itemBuilder: (context, index) {
                            final session = _sessionHistory[index];
                            return Card(
                              color: Colors.blueGrey[700],
                              margin: const EdgeInsets.symmetric(vertical: 3.0),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  '${index + 1}) ${session.stepCount}걸음, 평균 ${session.averageSpeed.toStringAsFixed(2)} m/s (${(session.endTime.difference(session.startTime).inSeconds / 60).toStringAsFixed(1)}분)',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Opacity(
                opacity: 0.9,
                child: Container(
                  height: 80,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.blueGrey[800],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black38)),
                  alignment: Alignment.center,
                  child: const Text(
                    "아직 보행 기록이 없습니다.",
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ),
              )
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true; // dispose 시작 플래그 설정
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _checkTimer?.cancel();
    flutterTts.stop();
    super.dispose();
    print("StepCounterPage disposed");
  }
}