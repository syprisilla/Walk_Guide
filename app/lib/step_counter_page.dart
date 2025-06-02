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
  bool _isDisposed = false; // dispose 상태 플래그

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5);
    flutterTts.setLanguage("ko-KR");

    requestPermission();
    loadSessions();

    // 사용자 맞춤형 프로필 초기화
    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    _userProfile = UserProfile.fromSessions(sessions);

    widget.onInitialized?.call(() => RealTimeSpeedService.getSpeed());
  }

  void _handleDetectedObjects(List<DetectedObjectInfo> objectsInfo) {
    if (!mounted || _isDisposed) return;
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
      if (!Hive.isBoxOpen('recent_steps')) {
        await Hive.openBox<DateTime>('recent_steps');
        debugPrint(" Hive 'recent_steps' 박스 열림 완료");
      }
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
      if (_isDisposed || !mounted) return; // mounted 추가 확인
      double totalAcceleration =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      double movement = (totalAcceleration - 9.8).abs();

      if (movement > movementThreshold) {
        _lastMovementTime = DateTime.now();
        if (!_isMoving) {
          if (mounted && !_isDisposed) {
            // setState 호출 전 mounted, _isDisposed 확인
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

    final delay = getGuidanceDelay(_userProfile.avgSpeed);

    String sizeDesc = objectInfo.sizeDescription;
    String message = "전방에";
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc 크기의";
    }
    message += " 장애물이 있습니다. 주의하세요.";

    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정... TTS 메시지: $message");

    await Future.delayed(delay);
    if (_isDisposed) return;

    await flutterTts.speak(message);
    debugPrint("🔊 안내 완료: $message");
    _lastGuidanceTime = DateTime.now();
  }

  void onStepCount(StepCount event) async {
    if (!mounted || _isDisposed) return;

    debugPrint(
        "걸음 수 이벤트 발생: ${event.steps}, 현재 _steps: $_steps, _initialSteps: $_initialSteps, _previousSteps: $_previousSteps");

    if (_initialSteps == null) {
      // 세션 시작 또는 앱 첫 실행 시
      _initialSteps = event.steps;
      _previousSteps = event.steps;
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now();
      RealTimeSpeedService.clear(delay: true);
      _steps = 0; // 새 세션 시작이므로 _steps는 0으로 초기화
      if (mounted && !_isDisposed) {
        setState(() {}); // UI에 초기값 반영 (예: 0걸음)
      }
      debugPrint("세션 시작: _initialSteps = $_initialSteps, _steps = $_steps");
      return;
    }

    // _initialSteps가 설정된 이후에는 _previousSteps를 기준으로 증분 계산
    int currentPedometerSteps = event.steps;
    int stepDelta =
        currentPedometerSteps - (_previousSteps ?? currentPedometerSteps);

    if (stepDelta > 0) {
      _steps += stepDelta;
      final baseTime = DateTime.now(); //  고정 기준 시간
      for (int i = 0; i < stepDelta; i++) {
        await RealTimeSpeedService.recordStep(
          baseTime.add(Duration(milliseconds: i * 100)), //  시간 차이 줘서 기록
        );
      }
      _lastMovementTime = DateTime.now();
      if (mounted && !_isDisposed) {
        setState(() {});
      }
    }
    _previousSteps = currentPedometerSteps; // 이전 pedometer 값 업데이트
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
    if (_isDisposed) return;
    if (_startTime == null || _steps == 0) {
      debugPrint("세션 저장 스킵: 시작 시간이 없거나 걸음 수가 0입니다.");
      // _steps와 _startTime 등은 다음 세션 시작 시 onStepCount에서 초기화됨
      // 다만, _isMoving 상태는 여기서 false로 바꿔주는 것이 좋을 수 있음 (startCheckingMovement와 연관)
      if (_isMoving && mounted && !_isDisposed) {
        // setState(() => _isMoving = false); // 이미 startCheckingMovement에서 처리할 수 있음
      }
      // _initialSteps와 _previousSteps는 pedometer의 절대값이므로 여기서 null로 만들면
      // 다음에 onStepCount가 호출될 때 새 세션처럼 동작함.
      _initialSteps = null;
      _previousSteps = null;
      _steps = 0; // UI 표시용 걸음수는 0으로
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

    _sessionHistory.insert(0, session); // 최신 기록을 맨 앞에 추가
    if (_sessionHistory.length > 20) {
      // 예시: 최대 20개 기록 유지
      _sessionHistory.removeLast();
    }

    final box = Hive.box<WalkSession>('walk_sessions');
    box.add(session);

    // Firestore 저장
    await FirestoreService.saveDailySteps(_steps);
    await FirestoreService.saveWalkingSpeed(getAverageSpeed());

    debugPrint("🟢 저장된 세션: $session");
    debugPrint("💾 Hive에 저장된 세션 수: ${box.length}");

    analyzeWalkingPattern();

    // 다음 세션을 위해 상태 초기화
    _steps = 0;
    _initialSteps = null;
    _previousSteps = null;
    _startTime = null;
    RealTimeSpeedService.clear(delay: true);
    if (mounted && !_isDisposed) setState(() {});
  }

  void startCheckingMovement() {
    if (_isDisposed) return;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isDisposed) {
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
        // 비정상 상태 수정
        if (mounted && !_isDisposed) {
          setState(() {
            _isMoving = false;
          });
        }
      } else if (_isMoving && _startTime == null) {
        // 세션 시작이 안됐는데 움직이는 상태로 되어있는 경우 (예: 앱 재시작 후)
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
    // 최근 데이터가 위로 오도록 정렬 (startTime 기준 내림차순)
    loadedSessions.sort((a, b) => b.startTime.compareTo(a.startTime));

    if (mounted && !_isDisposed) {
      setState(() {
        _sessionHistory = loadedSessions;
      });
    } else if (!_isDisposed) {
      _sessionHistory = loadedSessions;
    }
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");
    analyzeWalkingPattern();
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
                        height: 50,
                        width: 1,
                        color: Colors.white30,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
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
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _checkTimer?.cancel();
    flutterTts.stop();
    super.dispose();
    print("StepCounterPage disposed");
  }
}
