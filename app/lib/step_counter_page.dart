import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:camera/camera.dart';
// DetectedObject를 직접 사용하지 않으므로 google_mlkit_object_detection.dart import는 제거 가능
// import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import 'walk_session.dart';
import 'package:walk_guide/real_time_speed_service.dart';
import 'package:walk_guide/voice_guide_service.dart'; // isVoiceGuideEnabled 가져오기

// ObjectDetectionView와 DetectedObjectInfo를 import합니다.
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
  List<WalkSession> _sessionHistory = [];

  static const double movementThreshold = 1.5; // 움직임 감지 임계값

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5); // 기본 말하기 속도
    flutterTts.setLanguage("ko-KR"); // 한국어 설정
    requestPermission();
    loadSessions();
    widget.onInitialized?.call(() => RealTimeSpeedService.getSpeed());
  }

  // 콜백 파라미터 타입 변경: List<DetectedObject> -> List<DetectedObjectInfo>
  void _handleDetectedObjects(List<DetectedObjectInfo> objectsInfo) {
    if (!mounted) return;
    if (objectsInfo.isNotEmpty) {
      final DetectedObjectInfo firstObjectInfo = objectsInfo.first; // 가장 큰 객체 정보 사용
      guideWhenObjectDetected(firstObjectInfo); // 객체 정보 전달
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
      if (context.mounted) { // mounted 확인 후 showDialog 호출
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
      double totalAcceleration =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      double movement = (totalAcceleration - 9.8).abs(); // 중력 가속도(9.8m/s^2) 제외

      if (movement > movementThreshold) {
        _lastMovementTime = DateTime.now();
        if (!_isMoving) {
          if (mounted) {
            setState(() {
              _isMoving = true;
            });
          }
          debugPrint("움직임 감지!");
          // 움직임 감지 시 객체 탐지 콜백을 직접 호출하지 않고,
          // 카메라는 계속 프레임을 처리하며 _handleDetectedObjects가 호출될 것임.
        }
      }
    });
  }

  Duration getGuidanceDelay(double avgSpeed) {
    if (avgSpeed < 0.5) { // 매우 느린 속도
      return const Duration(seconds: 2);
    } else if (avgSpeed < 1.2) { // 보통 속도
      return const Duration(milliseconds: 1500);
    } else { // 빠른 속도
      return const Duration(seconds: 1);
    }
  }

  // 파라미터 변경: DetectedObjectInfo objectInfo
  void guideWhenObjectDetected(DetectedObjectInfo objectInfo) async {
    final now = DateTime.now();
    // 쿨다운 시간 (예: 3초) - 너무 자주 안내하지 않도록
    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!).inSeconds < 3) {
      debugPrint("⏳ 쿨다운 중 - 음성 안내 생략 (마지막 안내: $_lastGuidanceTime)");
      return;
    }

    // TTS 설정 확인
    bool voiceEnabled = await isVoiceGuideEnabled();
    if (!voiceEnabled) {
      debugPrint("🔇 음성 안내 비활성화됨 - 안내 생략");
      return;
    }

    double avgSpeed = RealTimeSpeedService.getSpeed();
    final delay = getGuidanceDelay(avgSpeed);

    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정... (객체: ${objectInfo.label}, 크기: ${objectInfo.sizeDescription})");
    await Future.delayed(delay);

    // 객체 크기 및 레이블 정보 활용
    String objectLabel = objectInfo.label ?? "장애물"; // 레이블 없으면 기본값 "장애물"
    String sizeDesc = objectInfo.sizeDescription; // "작은", "중간 크기의", "큰" 등
    String message = "전방에";
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc";
    }
    message += " $objectLabel. 주의하세요.";
    
    // 중복 안내 방지 로직 추가 (선택적)
    // static String? _lastSpokenMessage;
    // if (_lastSpokenMessage == message && now.difference(_lastGuidanceTime!).inSeconds < 10) {
    //   debugPrint("같은 내용 반복 안내 방지");
    //   return;
    // }

    await flutterTts.speak(message);
    debugPrint("🔊 안내 완료: $message");
    _lastGuidanceTime = DateTime.now();
    // _lastSpokenMessage = message;
  }

  void onStepCount(StepCount event) async {
    debugPrint("걸음 수 이벤트 발생: ${event.steps}");

    if (!mounted) return; // 위젯이 dispose된 후 호출 방지

    if (_initialSteps == null) {
      _initialSteps = event.steps;
      _previousSteps = event.steps; // 이전 걸음 수도 현재 걸음 수로 초기화
      _startTime = DateTime.now();
      _lastMovementTime = DateTime.now(); // 마지막 움직임 시간도 현재로 초기화
      RealTimeSpeedService.clear(); // 새 세션 시작 시 속도 데이터 초기화
      if (mounted) setState(() {});
      return;
    }

    int stepDelta = event.steps - (_previousSteps ?? event.steps); // null coalesce 추가
    if (stepDelta > 0) {
      _steps += stepDelta;
      final now = DateTime.now();
      for (int i = 0; i < stepDelta; i++) {
        RealTimeSpeedService.recordStep(now); // 실시간 속도 계산용 데이터 기록
        // Hive에 recent_steps를 저장하는 로직이 필요하다면 여기에 추가
        // 예: Hive.box<DateTime>('recent_steps').add(now);
      }
    }
    _previousSteps = event.steps; // 이전 걸음 수 업데이트
    _lastMovementTime = DateTime.now(); // 걸음이 감지되면 움직임으로 간주

    if (mounted) {
      setState(() {});
    }
  }

  void onStepCountError(error) {
    debugPrint('걸음 수 측정 오류: $error');
    if (!mounted) return;
    // 오류 발생 시 잠시 후 재시도 (선택적)
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        debugPrint('걸음 측정 재시도...');
        startPedometer();
      }
    });
  }

  double getAverageSpeed() {
    if (_startTime == null || _steps == 0) return 0;
    final durationInSeconds = DateTime.now().difference(_startTime!).inSeconds;
    if (durationInSeconds == 0) return 0;
    double stepLength = 0.7; // 평균 보폭 (m), 개인화 가능
    double distanceInMeters = _steps * stepLength;
    return distanceInMeters / durationInSeconds; // m/s
  }

  double getRealTimeSpeed() {
    return RealTimeSpeedService.getSpeed(); // 실시간 속도 서비스 사용
  }

  void _saveSessionData() {
    if (_startTime == null || _steps == 0) {
      debugPrint("세션 저장 스킵: 시작 시간이 없거나 걸음 수가 0입니다.");
      // 세션이 시작되지 않았거나 유효하지 않으면, 관련 변수들을 초기화할 수 있습니다.
      _steps = 0;
      _initialSteps = null;
      _previousSteps = null;
      _startTime = null;
      RealTimeSpeedService.clear(); // 속도 데이터도 초기화
      if (mounted) setState(() {});
      return;
    }


    final endTime = DateTime.now();
    final session = WalkSession(
      startTime: _startTime!,
      endTime: endTime,
      stepCount: _steps,
      averageSpeed: getAverageSpeed(),
    );

    _sessionHistory.add(session); // UI용 리스트에 추가
    final box = Hive.box<WalkSession>('walk_sessions'); // Hive 박스 열기
    box.add(session); // Hive에 저장

    debugPrint("🟢 저장된 세션: $session");
    debugPrint("💾 Hive에 저장된 세션 수: ${box.length}");

    analyzeWalkingPattern(); // 저장 후 패턴 분석

    // 다음 세션을 위해 상태 초기화
    _steps = 0;
    _initialSteps = null; // 다음 세션 시작 시 pedometer의 현재 값을 기준으로 다시 설정됨
    _previousSteps = null; // 위와 동일
    _startTime = null; // 새 세션 시작 시 다시 설정됨
    RealTimeSpeedService.clear(); // 속도 데이터 초기화
    if (mounted) setState((){}); // UI 업데이트
  }

  void startCheckingMovement() {
    _checkTimer?.cancel(); // 이전 타이머가 있다면 취소
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) { // 체크 간격 조정
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lastMovementTime != null && _isMoving) { // 움직이는 중에만 정지 감지
        final diff = DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        // 정지 감지 임계 시간 (예: 2초)
        if (diff >= 2000) { // 2초 이상 움직임 없으면 정지로 판단
          if (mounted) {
            setState(() {
              _isMoving = false; // 정지 상태로 변경
            });
          }
          debugPrint("정지 감지 (2초 이상 움직임 없음)!");
          _saveSessionData(); // 정지 시 현재까지의 보행을 세션으로 저장
        }
      } else if (_lastMovementTime == null && _isMoving) {
        // _lastMovementTime이 null인데 _isMoving이 true인 비정상적 상태 방지
        if (mounted) {
            setState(() {
                _isMoving = false;
            });
        }
      }
    });
  }

  void loadSessions() {
    final box = Hive.box<WalkSession>('walk_sessions');
    // Hive 박스가 변경될 때마다 UI를 업데이트하도록 ValueListenableBuilder를 사용하는 것이 더 반응적일 수 있으나,
    // initState에서 한번 로드하는 현재 방식도 유효합니다.
    final loadedSessions = box.values.toList();
    if (mounted) {
      setState(() {
        _sessionHistory = loadedSessions.reversed.toList(); // 최신 기록이 위로 오도록
      });
    } else {
      _sessionHistory = loadedSessions.reversed.toList();
    }
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");
    analyzeWalkingPattern();
  }

  void analyzeWalkingPattern() {
    if (_sessionHistory.isEmpty) {
      debugPrint("⚠️ 보행 데이터가 없어 패턴 분석을 건너<0xE3><0x8A><0x8D>니다.");
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
                    onObjectsDetected: _handleDetectedObjects, // 수정된 콜백 연결
                  )
                : Container( /* ... 카메라 없음 UI ... */
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
          Positioned( /* ... 상단 정보 UI ... */
              top: 20,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75), // 배경 투명도 조절
                    borderRadius: BorderRadius.circular(12), // 모서리 둥글게
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
                    crossAxisAlignment: CrossAxisAlignment.center, // 중앙 정렬
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _isMoving ? '🚶 보행 중' : '🛑 정지 상태',
                              style: const TextStyle(
                                  fontSize: 16, // 폰트 크기 조절
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_steps 걸음',
                              style: const TextStyle(
                                  fontSize: 20, // 폰트 크기 조절
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container( // 구분선
                        height: 50, width: 1, color: Colors.white30, margin: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('평균 속도',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.white70)), // 레이블 폰트 조절
                            const SizedBox(height: 2),
                            Text(
                              '${getAverageSpeed().toStringAsFixed(2)} m/s',
                              style: const TextStyle(
                                  fontSize: 18, // 값 폰트 조절
                                  color: Colors.lightGreenAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6), // 간격 조절
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
          if (_sessionHistory.isNotEmpty) // 세션 기록이 있을 때만 표시
            Positioned( /* ... 하단 세션 기록 UI ... */
              bottom: 20,
              left: 20,
              right: 20,
              child: Opacity(
                opacity: 0.9, // 투명도 조절
                child: Container(
                  height: 160, // 높이 조절
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.blueGrey[800], // 배경색 변경
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
                          itemCount: _sessionHistory.length > 5 ? 5 : _sessionHistory.length, // 최근 5개만 표시
                          itemBuilder: (context, index) {
                            final session = _sessionHistory[index]; // 이미 reversed 되어 있음
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
          else // 세션 기록이 없을 때 메시지 표시
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Opacity(
                opacity: 0.9,
                child: Container(
                  height: 80, // 높이 조절
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
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _checkTimer?.cancel();
    flutterTts.stop(); // TTS 중지
    super.dispose();
  }
}