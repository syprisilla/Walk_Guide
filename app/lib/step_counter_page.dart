// File: lib/step_counter_page.dart
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:camera/camera.dart';

import 'walk_session.dart';
import 'package:walk_guide/real_time_speed_service.dart';
import 'package:walk_guide/voice_guide_service.dart';


import './ObjectDetection/object_detection_view.dart'; 

import 'package:walk_guide/user_profile.dart';
import 'package:walk_guide/services/firestore_service.dart';

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
  late UserProfile _userProfile;
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
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    print("StepCounterPage initState");

    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5);
    flutterTts.setLanguage("ko-KR");

    requestPermission();
    loadSessions();

    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    _userProfile = UserProfile.fromSessions(sessions);

    widget.onInitialized?.call(() => RealTimeSpeedService.getSpeed());
  }

  Future<void> _setPortraitOrientation() async {
    print("StepCounterPage: Setting orientation to Portrait in dispose");
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }


  void _handleDetectedObjects(List<DetectedObjectInfo> objectsInfo) {
    if (!mounted || _isDisposed) return;
    if (objectsInfo.isNotEmpty) {
      final DetectedObjectInfo firstObjectInfo = objectsInfo.first;
      guideWhenObjectDetected(firstObjectInfo);
    }
  }

  Future<void> requestPermission() async {
    if (_isDisposed) return;
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
    }

    if (status.isGranted) {
      if (!Hive.isBoxOpen('recent_steps')) {
        await Hive.openBox<DateTime>('recent_steps');
        debugPrint(" Hive 'recent_steps' 박스 열림 완료");
      }
      if (mounted && !_isDisposed) { 
        startPedometer();
        startAccelerometer();
        startCheckingMovement();
      }
    } else {
      if (mounted && !_isDisposed) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('권한 필요'),
            content: const Text('걸음 측정을 위해 활동 인식 권한을 허용해 주세요.'),
            actions: [
              TextButton(
                onPressed: () {
                  if(mounted) Navigator.of(context).pop();
                } ,
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  void startPedometer() {
    if (_isDisposed || !mounted) return;
    _stepCountSubscription?.cancel();
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountSubscription = _stepCountStream.listen(
      onStepCount,
      onError: onStepCountError,
      cancelOnError: true,
    );
  }

  void startAccelerometer() {
    if (_isDisposed || !mounted) return;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      if (_isDisposed || !mounted) return;
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

  void guideWhenObjectDetected(DetectedObjectInfo objectInfo) async {
    if (_isDisposed || !mounted) return;
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

    final delay = getGuidanceDelay(_userProfile.avgSpeed);

    String sizeDesc = objectInfo.sizeDescription;
    String positionDesc = objectInfo.positionalDescription;

    // MODIFIED: Unified object naming to "장애물"
    String message = "$positionDesc에"; 
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc 크기의";
    }
    // Always use "장애물" regardless of objectInfo.label
    message += " 장애물이 있습니다. 주의하세요."; 

    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정... TTS 메시지: $message");

    await Future.delayed(delay);
    if (_isDisposed || !mounted) return;

    await flutterTts.speak(message);
    debugPrint("🔊 안내 완료: $message");
    _lastGuidanceTime = DateTime.now();
  }

  void onStepCount(StepCount event) async {
    if (_isDisposed || !mounted) return;

    debugPrint(
        "걸음 수 이벤트 발생: ${event.steps}, 현재 _steps: $_steps, _initialSteps: $_initialSteps, _previousSteps: $_previousSteps");

    if (_initialSteps == null) {
      _initialSteps = event.steps;
      _previousSteps = event.steps;
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now();
      RealTimeSpeedService.clear(delay: true);
      _steps = 0;
      if (mounted && !_isDisposed) {
        setState(() {});
      }
      debugPrint("세션 시작: _initialSteps = $_initialSteps, _steps = $_steps");
      return;
    }

    int currentPedometerSteps = event.steps;
    int stepDelta =
        currentPedometerSteps - (_previousSteps ?? currentPedometerSteps);

    if (stepDelta > 0) {
      _steps += stepDelta;
      final baseTime = DateTime.now();
      for (int i = 0; i < stepDelta; i++) {
        await RealTimeSpeedService.recordStep(
          baseTime.add(Duration(milliseconds: i * 100)),
        );
      }
      _lastMovementTime = DateTime.now();
      if (mounted && !_isDisposed) {
        setState(() {});
      }
    }
    _previousSteps = currentPedometerSteps;
    debugPrint(
        "걸음 업데이트: stepDelta = $stepDelta, _steps = $_steps, _previousSteps = $_previousSteps");
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

  Future<void> _saveSessionData() async {
    if (_isDisposed || !mounted) return;
    if (_startTime == null || _steps == 0) {
      debugPrint("세션 저장 스킵: 시작 시간이 없거나 걸음 수가 0입니다.");
      _initialSteps = null;
      _previousSteps = null;
      _steps = 0;
      _startTime = null;
      RealTimeSpeedService.clear(delay: true);
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

    _sessionHistory.insert(0, session);
    if (_sessionHistory.length > 20) {
      _sessionHistory.removeLast();
    }

    final box = Hive.box<WalkSession>('walk_sessions');
    box.add(session);

    if (mounted && !_isDisposed) { 
        await FirestoreService.saveDailySteps(_steps);
        await FirestoreService.saveWalkingSpeed(getAverageSpeed());
    }

    debugPrint("🟢 저장된 세션: $session");
    debugPrint("💾 Hive에 저장된 세션 수: ${box.length}");

    if (mounted && !_isDisposed) {
        analyzeWalkingPattern();
    }

    _steps = 0;
    _initialSteps = null;
    _previousSteps = null;
    _startTime = null;
    RealTimeSpeedService.clear(delay: true);
    if (mounted && !_isDisposed) setState(() {});
  }

  void startCheckingMovement() {
    if (_isDisposed || !mounted) return;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      if (_lastMovementTime != null && _isMoving) {
        final diff =
            DateTime.now().difference(_lastMovementTime!).inMilliseconds;
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
      } else if (_isMoving && _startTime == null) {
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
    loadedSessions.sort((a, b) => b.startTime.compareTo(a.startTime));

    if (mounted && !_isDisposed) {
      setState(() {
        _sessionHistory = loadedSessions;
      });
    } else if (!_isDisposed) { 
      _sessionHistory = loadedSessions;
    }
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");
    if (mounted && !_isDisposed) { 
        analyzeWalkingPattern();
    }
  }

  void analyzeWalkingPattern() {
    if (_isDisposed || _sessionHistory.isEmpty) {
      debugPrint("⚠️ 보행 데이터가 없어 패턴 분석을 건너뜁니다.");
      return;
    }

    double totalSpeed = 0;
    int totalSteps = 0;
    int totalDurationSeconds = 0;

    for (var session in _sessionHistory) {
      totalSpeed += session.averageSpeed;
      totalSteps += session.stepCount;
      totalDurationSeconds +=
          session.endTime.difference(session.startTime).inSeconds;
    }

    int sessionCount = _sessionHistory.length;
    double overallAvgSpeed = sessionCount > 0 ? totalSpeed / sessionCount : 0;
    double avgStepsPerSession =
        sessionCount > 0 ? totalSteps / sessionCount : 0;
    double avgDurationPerSessionSeconds =
        sessionCount > 0 ? totalDurationSeconds / sessionCount : 0;

    debugPrint("📊 보행 패턴 분석 결과:");
    debugPrint("- 전체 평균 속도: ${overallAvgSpeed.toStringAsFixed(2)} m/s");
    debugPrint("- 세션 당 평균 걸음 수: ${avgStepsPerSession.toStringAsFixed(1)} 걸음");
    debugPrint(
        "- 세션 당 평균 시간: ${(avgDurationPerSessionSeconds / 60).toStringAsFixed(1)} 분 (${avgDurationPerSessionSeconds.toStringAsFixed(1)} 초)");
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
              top: 10,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 2.0, horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
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
                                  fontSize: 6,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_steps 걸음',
                              style: const TextStyle(
                                  fontSize: 7,
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 25,
                        width: 1,
                        color: Colors.white30,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('평균 속도',
                                style: TextStyle(
                                    fontSize: 6, color: Colors.white70)),
                            const SizedBox(height: 1),
                            Text(
                              '${getAverageSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 7,
                                  color: Colors.lightGreenAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text('실시간 속도',
                                style: TextStyle(
                                    fontSize: 6, color: Colors.white70)),
                            const SizedBox(height: 1),
                            Text(
                              '${getRealTimeSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 6,
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
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _sessionHistory.length > 5
                              ? 5
                              : _sessionHistory.length,
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
                bottom: 20,
                left: 20,
                right: 20,
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
                )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true; 
    print("StepCounterPage dispose initiated");

    _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    
    flutterTts.stop();

    _setPortraitOrientation();

    super.dispose();
    print("StepCounterPage disposed successfully");
  }
}