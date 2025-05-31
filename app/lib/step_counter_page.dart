import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:camera/camera.dart'; // 카메라 사용을 위해

import 'walk_session.dart';
import 'package:walk_guide/real_time_speed_service.dart';
import 'package:walk_guide/voice_guide_service.dart';

// ObjectDetectionView와 DetectedObjectInfo, ObjectHorizontalLocation를 사용하기 위해 import
import './ObjectDetection/object_detection_view.dart';

import 'package:walk_guide/user_profile.dart'; // UserProfile 경로 확인
import 'package:flutter/services.dart';

class StepCounterPage extends StatefulWidget {
  final void Function(double Function())? onInitialized;
  final List<CameraDescription> cameras; // 카메라 리스트를 받도록 수정

  const StepCounterPage({
    super.key,
    this.onInitialized,
    required this.cameras, // cameras를 필수로 받도록 함
  });

  @override
  State<StepCounterPage> createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> {
  late UserProfile _userProfile; // 사용자 프로필
  late Stream<StepCount> _stepCountStream;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _checkTimer; // 움직임 감지 타이머
  late FlutterTts flutterTts; // TTS 엔진

  int _steps = 0; // 현재 세션 걸음 수
  int? _initialSteps; // Pedometer 초기 걸음 수
  int? _previousSteps; // Pedometer 이전 걸음 수 (증분 계산용)
  DateTime? _startTime; // 세션 시작 시간
  DateTime? _lastMovementTime; // 마지막 움직임 감지 시간
  DateTime? _lastGuidanceTime; // 마지막 음성 안내 시간 (쿨다운용)

  bool _isMoving = false; // 현재 움직임 상태
  List<WalkSession> _sessionHistory = []; // 보행 세션 기록

  static const double movementThreshold = 1.5; // 움직임 감지 임계값 (가속도계)
  bool _isDisposed = false; // dispose 상태 플래그

  @override
void initState() {
  super.initState();
  _isDisposed = false;

  // 화면을 가로 모드로 설정
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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

  // ObjectDetectionView로부터 감지된 객체 정보를 받는 콜백 함수
  void _handleDetectedObjects(List<DetectedObjectInfo> objectsInfo) {
    if (!mounted || _isDisposed) return; // 위젯이 화면에 없거나 dispose된 경우 무시
    if (objectsInfo.isNotEmpty) {
      // 여러 객체가 감지될 수 있으나, 여기서는 첫 번째(또는 가장 큰) 객체만 처리
      final DetectedObjectInfo firstObjectInfo = objectsInfo.first;
      guideWhenObjectDetected(firstObjectInfo); // 객체 감지 시 음성 안내 함수 호출
    }
  }

  Future<void> requestPermission() async {
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
    }

    if (status.isGranted) {
      // recent_steps 박스가 열려있지 않다면 열기
      if (!Hive.isBoxOpen('recent_steps')) {
        await Hive.openBox<DateTime>('recent_steps');
        debugPrint(" Hive 'recent_steps' 박스 열림 완료");
      }
      startPedometer(); // 걸음 수 감지 시작
      startAccelerometer(); // 가속도계 감지 시작 (움직임 파악용)
      startCheckingMovement(); // 주기적으로 움직임 상태 확인 시작
    } else {
      // 권한 거부 시 사용자에게 알림
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
    _stepCountSubscription?.cancel(); // 기존 구독 취소
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountSubscription = _stepCountStream.listen(
      onStepCount, // 걸음 수 이벤트 발생 시 호출
      onError: onStepCountError, // 오류 발생 시 호출
      cancelOnError: true,
    );
  }

  void startAccelerometer() {
    if (_isDisposed) return;
    _accelerometerSubscription?.cancel(); // 기존 구독 취소
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      if (_isDisposed || !mounted) return; // mounted 추가 확인
      // 전체 가속도 계산 (중력 제외)
      double totalAcceleration =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      double movement = (totalAcceleration - 9.8).abs(); // 9.8은 중력 가속도 근사값

      if (movement > movementThreshold) {
        _lastMovementTime = DateTime.now(); // 마지막 움직임 시간 업데이트
        if (!_isMoving) {
          // 움직임 상태로 변경 (UI 업데이트는 startCheckingMovement에서 처리할 수도 있음)
          if (mounted && !_isDisposed) {
            setState(() {
              _isMoving = true;
            });
          }
          debugPrint("움직임 감지 (가속도계 기반)!");
        }
      }
    });
  }

  // 사용자 평균 속도에 따른 음성 안내 지연 시간 계산
  Duration getGuidanceDelay(double avgSpeed) {
    if (avgSpeed < 0.5) { // 느린 속도
      return const Duration(seconds: 2);
    } else if (avgSpeed < 1.2) { // 보통 속도
      return const Duration(milliseconds: 1500);
    } else { // 빠른 속도
      return const Duration(seconds: 1);
    }
  }

  // 객체 감지 시 음성 안내를 제공하는 함수
  void guideWhenObjectDetected(DetectedObjectInfo objectInfo) async {
    if (_isDisposed) return; // dispose된 경우 중단
    final now = DateTime.now();
    // 쿨다운: 마지막 안내 후 3초 이내에는 다시 안내하지 않음
    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!).inSeconds < 3) {
      debugPrint("⏳ 쿨다운 중 - 음성 안내 생략 (마지막 안내: $_lastGuidanceTime)");
      return;
    }

    bool voiceEnabled = await isVoiceGuideEnabled(); // 음성 안내 설정값 확인
    if (!voiceEnabled) {
      debugPrint("🔇 음성 안내 비활성화됨 - 안내 생략");
      return;
    }

    final delay = getGuidanceDelay(_userProfile.avgSpeed); // 사용자 평균 속도 기반 지연시간

    // TTS 메시지 생성 (위치 + 크기)
    String locationDesc = objectInfo.horizontalLocationDescription; // "좌측", "중앙", "우측"
    String sizeDesc = objectInfo.sizeDescription; // "작은", "중간 크기의", "큰"

    String message = "$locationDesc 에"; // 예: "좌측에"
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc"; // 예: "좌측에 작은" (크기가 unknown이면 이 부분은 비어있을 수 있음)
    }
    message += " 장애물이 있습니다. 주의하세요."; // 예: "좌측에 작은 장애물이 있습니다. 주의하세요."
    
    // 중앙에 위치한 경우 "전방에"로 대체하는 것을 고려 (선택 사항)
    // if (objectInfo.horizontalLocation == ObjectHorizontalLocation.center && locationDesc == "중앙") {
    //   message = "전방에";
    //    if (sizeDesc.isNotEmpty) {
    //      message += " $sizeDesc";
    //    }
    //    message += " 장애물이 있습니다. 주의하세요.";
    // }


    debugPrint("🕒 ${delay.inMilliseconds}ms 후 안내 예정... TTS 메시지: $message");

    await Future.delayed(delay); // 계산된 지연시간만큼 대기
    if (_isDisposed) return; // 대기 중 dispose될 수 있으므로 확인

    await flutterTts.speak(message); // TTS 발화
    debugPrint("🔊 안내 완료: $message");
    _lastGuidanceTime = DateTime.now(); // 마지막 안내 시간 기록
  }


  void onStepCount(StepCount event) async {
    if (!mounted || _isDisposed) return; // 위젯 상태 확인

    debugPrint(
        "걸음 수 이벤트: ${event.steps}, 현재 _steps: $_steps, _initialSteps: $_initialSteps, _previousSteps: $_previousSteps");

    if (_initialSteps == null) {
      // 세션 시작 또는 앱 처음 실행 시
      _initialSteps = event.steps; // Pedometer에서 제공하는 누적 걸음 수
      _previousSteps = event.steps; // 이전 값도 동일하게 초기화
      _startTime = DateTime.now();    // 현재 세션 시작 시간 기록
      _lastMovementTime = DateTime.now(); // 마지막 움직임 시간 초기화
      RealTimeSpeedService.clear(delay: true); // 이전 속도 기록 지연 삭제
      _steps = 0; // 현재 세션의 걸음 수는 0으로 시작
      if (mounted && !_isDisposed) {
        setState(() {}); // UI에 초기값(0걸음) 반영
      }
      debugPrint("세션 시작: _initialSteps = $_initialSteps, _steps = $_steps");
      return;
    }

    // _initialSteps가 설정된 이후에는 _previousSteps를 기준으로 증분 계산
    int currentPedometerSteps = event.steps;
    int stepDelta = currentPedometerSteps - (_previousSteps ?? currentPedometerSteps); // 증가한 걸음 수

    if (stepDelta > 0) { // 걸음 수가 증가했을 때만 처리
      _steps += stepDelta; // 현재 세션 걸음 수에 더함
      final baseTime = DateTime.now(); // 각 걸음 기록을 위한 기준 시간
      for (int i = 0; i < stepDelta; i++) {
        // 각 걸음을 약간의 시간차를 두고 기록하여 속도 계산의 정확도 향상 시도
        await RealTimeSpeedService.recordStep(
          baseTime.add(Duration(milliseconds: i * 100)),
        );
      }
      _lastMovementTime = DateTime.now(); // 마지막 움직임 시간 업데이트
      if (mounted && !_isDisposed) {
        setState(() {}); // UI 업데이트
      }
    }
    _previousSteps = currentPedometerSteps; // 다음 증분 계산을 위해 이전 pedometer 값 업데이트
    debugPrint(
        "걸음 업데이트: stepDelta = $stepDelta, _steps = $_steps, _previousSteps = $_previousSteps");
  }


  void onStepCountError(error) {
    if (_isDisposed) return;
    debugPrint('걸음 수 측정 오류: $error');
    // 오류 발생 시 5초 후 재시도
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_isDisposed) {
        debugPrint('걸음 측정 재시도...');
        startPedometer();
      }
    });
  }

  // 현재 세션의 평균 속도 계산
  double getAverageSpeed() {
    if (_startTime == null || _steps == 0) return 0.0;
    final durationInSeconds = DateTime.now().difference(_startTime!).inSeconds;
    if (durationInSeconds == 0) return 0.0;
    double stepLength = 0.7; // 평균 보폭 (미터 단위, 사용자화 가능)
    double distanceInMeters = _steps * stepLength;
    return distanceInMeters / durationInSeconds; // m/s
  }

  // 실시간 속도 가져오기 (RealTimeSpeedService 사용)
  double getRealTimeSpeed() {
    return RealTimeSpeedService.getSpeed();
  }

  // 현재 세션 데이터 저장
  void _saveSessionData() {
    if (_isDisposed) return;
    // 세션 시작 시간이 없거나 걸음 수가 0이면 저장하지 않음
    if (_startTime == null || _steps == 0) {
      debugPrint("세션 저장 스킵: 시작 시간이 없거나 걸음 수가 0입니다.");
      // 상태 초기화 (다음 세션 준비)
      _initialSteps = null;
      _previousSteps = null;
      _steps = 0;
      _startTime = null;
      RealTimeSpeedService.clear(delay: true); // 이전 속도 기록 지연 삭제
      if (mounted && !_isDisposed) setState(() {}); // UI에 반영
      return;
    }

    final endTime = DateTime.now(); // 현재 시간을 종료 시간으로
    final session = WalkSession(
      startTime: _startTime!,
      endTime: endTime,
      stepCount: _steps,
      averageSpeed: getAverageSpeed(),
    );

    _sessionHistory.insert(0, session); // 최근 기록을 맨 앞에 추가
    if (_sessionHistory.length > 20) { // 최대 20개 기록 유지 (예시)
      _sessionHistory.removeLast();
    }

    final box = Hive.box<WalkSession>('walk_sessions'); // Hive 박스 가져오기
    box.add(session); // 세션 데이터 Hive에 저장

    debugPrint("🟢 저장된 세션: $session");
    debugPrint("💾 Hive에 저장된 세션 수: ${box.length}");

    analyzeWalkingPattern(); // 보행 패턴 분석 (선택적 기능)

    // 다음 세션을 위해 상태 초기화
    _steps = 0;
    _initialSteps = null;
    _previousSteps = null;
    _startTime = null;
    RealTimeSpeedService.clear(delay: true);
    if (mounted && !_isDisposed) setState(() {}); // UI 업데이트
  }

  // 주기적으로 움직임 상태를 확인하는 타이머 시작
  void startCheckingMovement() {
    if (_isDisposed) return;
    _checkTimer?.cancel(); // 기존 타이머 취소
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isDisposed) { // 위젯 상태 확인
        timer.cancel();
        return;
      }
      if (_lastMovementTime != null && _isMoving) {
        // 마지막 움직임 감지 후 2초 이상 경과하면 정지 상태로 간주
        final diff = DateTime.now().difference(_lastMovementTime!).inMilliseconds;
        if (diff >= 2000) { // 2초 (2000ms)
          if (mounted && !_isDisposed) {
            setState(() {
              _isMoving = false; // 정지 상태로 변경
            });
          }
          debugPrint("정지 감지 (2초 이상 움직임 없음)!");
          _saveSessionData(); // 정지 시 세션 데이터 저장
        }
      } else if (_lastMovementTime == null && _isMoving) {
        // 비정상 상태 (움직임 상태인데 마지막 움직임 시간이 없는 경우) 수정
        if (mounted && !_isDisposed) {
          setState(() {
            _isMoving = false;
          });
        }
      } else if (_isMoving && _startTime == null) {
        // 비정상 상태 (세션 시작 전인데 움직임 상태인 경우, 예: 앱 재시작 후)
        if (mounted && !_isDisposed) {
          setState(() {
            _isMoving = false;
          });
        }
      }
    });
  }

  // Hive에서 저장된 세션 불러오기
  void loadSessions() {
    if (_isDisposed) return;
    final box = Hive.box<WalkSession>('walk_sessions');
    final loadedSessions = box.values.toList();
    // 최근 데이터가 위로 오도록 정렬 (startTime 기준 내림차순)
    loadedSessions.sort((a, b) => b.startTime.compareTo(a.startTime));

    if (mounted && !_isDisposed) {
      setState(() {
        _sessionHistory = loadedSessions; // UI에 반영
      });
    } else if (!_isDisposed) {
      // setState를 호출할 수 없는 경우 (예: initState에서 호출)
      _sessionHistory = loadedSessions;
    }
    debugPrint("📦 불러온 세션 수: ${_sessionHistory.length}");
    analyzeWalkingPattern(); // 보행 패턴 분석 (선택적)
  }

  // 보행 패턴 분석 (예시 함수)
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
        sessionCount > 0 ? totalSteps / sessionCount.toDouble() : 0; // double로 변경
    double avgDurationPerSessionSeconds =
        sessionCount > 0 ? totalDurationSeconds / sessionCount.toDouble() : 0; // double로 변경

    debugPrint("📊 보행 패턴 분석 결과:");
    debugPrint("- 전체 평균 속도: ${overallAvgSpeed.toStringAsFixed(2)} m/s");
    debugPrint("- 세션 당 평균 걸음 수: ${avgStepsPerSession.toStringAsFixed(1)} 걸음");
    debugPrint(
        "- 세션 당 평균 시간: ${(avgDurationPerSessionSeconds / 60).toStringAsFixed(1)} 분 (${avgDurationPerSessionSeconds.toStringAsFixed(1)} 초)");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보행 중'),
        // 뒤로가기 버튼 누르면 세션 저장 및 리소스 정리
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isMoving && _startTime != null && _steps > 0) {
              // 보행 중이었다면 현재 세션 저장
              _saveSessionData();
            } else {
              // 보행 중이 아니었거나, 유효한 세션 데이터가 없다면
              // _initialSteps 등을 null로 만들어 다음 pedometer 이벤트 시 새 세션으로 시작하도록 유도
              _initialSteps = null;
              _previousSteps = null;
              _steps = 0;
              _startTime = null;
              RealTimeSpeedService.clear(delay: false); // 즉시 삭제
            }
            Navigator.of(context).pop();
          },
        ),
      ),
      body: PopScope( // Android 뒤로가기 버튼 제어
        canPop: false, // 기본 뒤로가기 동작 막기
        onPopInvoked: (didPop) {
          if (didPop) return; // 이미 pop된 경우 무시
          if (_isMoving && _startTime != null && _steps > 0) {
            _saveSessionData();
          } else {
            _initialSteps = null;
            _previousSteps = null;
            _steps = 0;
            _startTime = null;
            RealTimeSpeedService.clear(delay: false);
          }
          Navigator.of(context).pop();
        },
        child: Stack(
          children: [
            // 카메라 프리뷰 및 객체 탐지 UI
            Positioned.fill(
              child: (widget.cameras.isNotEmpty)
                  ? ObjectDetectionView(
                      cameras: widget.cameras,
                      onObjectsDetected: _handleDetectedObjects, // 콜백 연결
                      resolutionPreset: ResolutionPreset.high, // 해상도 설정 (예시)
                    )
                  : Container( // 카메라 사용 불가 시 안내 메시지
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
            // 보행 정보 표시 UI (상단)
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
                      color: Colors.black.withOpacity(0.75), // 반투명 배경
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
                        Container( // 구분선
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
            // 최근 보행 기록 표시 UI (하단)
            if (_sessionHistory.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Opacity(
                  opacity: 0.9,
                  child: Container(
                    height: 160, // 높이 조절 가능
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blueGrey[800], // 어두운 배경
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
                            itemCount: _sessionHistory.length > 5 // 최근 5개만 표시 (예시)
                                ? 5
                                : _sessionHistory.length,
                            itemBuilder: (context, index) {
                              final session = _sessionHistory[index];
                              return Card(
                                color: Colors.blueGrey[700], // 카드 배경색
                                margin: const EdgeInsets.symmetric(vertical: 3.0),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    '${index + 1}) ${session.stepCount}걸음, 평균 ${session.averageSpeed.toStringAsFixed(2)} m/s (${(session.endTime.difference(session.startTime).inSeconds / 60).toStringAsFixed(1)}분)',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.white),
                                    overflow: TextOverflow.ellipsis, // 긴 텍스트 처리
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
            else // 보행 기록이 없을 때 표시
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
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true; // dispose 상태로 설정
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _checkTimer?.cancel();
    flutterTts.stop(); // TTS 중지
    // _saveSessionData(); // 페이지 종료 시 현재 세션 저장 (선택적: AppBar의 뒤로가기 버튼에서 이미 처리)
    super.dispose();
    print("StepCounterPage disposed");
  }
}