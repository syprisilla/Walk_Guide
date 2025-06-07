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
  bool _isCurrentlySpeaking = false;
  final List<String> _ttsQueue = [];
  String? _lastEnqueuedMessage; // 마지막으로 큐에 추가된 메시지


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

    _initTts(); 

    requestPermission();
    loadSessions();

    final box = Hive.box<WalkSession>('walk_sessions');
    final sessions = box.values.toList();
    _userProfile = UserProfile.fromSessions(sessions);

    widget.onInitialized?.call(() => RealTimeSpeedService.getSpeed());
  }

  void _initTts() {
    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5); // 음성 속도
    flutterTts.setLanguage("ko-KR"); // 한국어 설정

    flutterTts.setCompletionHandler(() {
      if (mounted && !_isDisposed) {
        setState(() { // UI 변경이 있을 수 있으므로 setState 사용
          _isCurrentlySpeaking = false;
        });
        _speakNextInQueue(); 
      } else if (!_isDisposed) { // mounted 되지 않았지만 dispose 되지도 않은 경우
        _isCurrentlySpeaking = false;
        _speakNextInQueue();
      }
    });

    flutterTts.setErrorHandler((msg) {
       if (mounted && !_isDisposed) {
        setState(() { // UI 변경이 있을 수 있으므로 setState 사용
          _isCurrentlySpeaking = false;
        });
         debugPrint("TTS Error: $msg");
        _speakNextInQueue(); 
      } else if (!_isDisposed) {
         _isCurrentlySpeaking = false;
         debugPrint("TTS Error (not mounted): $msg");
        _speakNextInQueue();
      }
    });
  }

  void _addToTtsQueue(String message) {
    if (_isDisposed) return;

    // 만약 큐가 너무 길거나 (예: 2개 이상) 현재 말하는 중이고,
    // 마지막에 큐에 넣은 메시지와 동일한 내용이면 중복 추가 방지 (선택적 개선)
    // if (_isCurrentlySpeaking && _ttsQueue.isNotEmpty && _ttsQueue.last == message) {
    //   debugPrint(" 동일 메시지 큐 추가 방지: $message");
    //   return;
    // }
    // if (_ttsQueue.length >= 1 && _isCurrentlySpeaking) { // 큐가 1개 이상 있고, 현재 말하는 중이면
    //    debugPrint("TTS 큐가 이미 있고 재생 중, 새 메시지로 교체: $message");
    //   _ttsQueue.clear(); // 기존 큐 비우고 새 메시지만 추가 (최신 정보 우선)
    // }
    
    // 간단한 큐 관리: 큐에 메시지가 1개만 있도록 유지 (가장 최신 정보만 안내)
    if (_isCurrentlySpeaking) { // 현재 뭔가 말하고 있다면
        if (_ttsQueue.isNotEmpty) { // 큐에 이미 대기중인 메시지가 있다면
            _ttsQueue.removeAt(0); // 가장 오래된 대기 메시지 제거
        }
    } else if (_ttsQueue.isNotEmpty) { // 현재 말하고 있지 않지만 큐에 뭔가 있다면 (이전 것이 완료되고 다음 것 재생 직전)
        _ttsQueue.clear(); // 일단 비우고 최신 것으로
    }


    _ttsQueue.add(message);
    _lastEnqueuedMessage = message; // 마지막으로 큐에 넣은 메시지 기록
    
    if (!_isCurrentlySpeaking) {
      _speakNextInQueue();
    }
  }

  void _speakNextInQueue() {
    if (_isDisposed || _ttsQueue.isEmpty || _isCurrentlySpeaking) {
      return;
    }
    
    if (mounted && !_isDisposed) {
         // setState는 _isCurrentlySpeaking 변경 시 UI 업데이트가 필요하다면 사용
         // 여기서는 TTS 시작 직후이므로, setCompletionHandler에서 false로 바꿀 때 UI 업데이트가 주 목적
    }
    _isCurrentlySpeaking = true;


    String messageToSpeak = _ttsQueue.removeAt(0);
    
    flutterTts.speak(messageToSpeak).then((result) {
        // speak 호출 자체의 성공 여부 (Android: 1 == success)
        // 실제 음성 출력이 완료된 것은 setCompletionHandler에서 처리
        if (result != 1) { 
            if (mounted && !_isDisposed) {
                setState(() { _isCurrentlySpeaking = false; });
            } else if (!_isDisposed) {
                 _isCurrentlySpeaking = false;
            }
            debugPrint("TTS speak() call failed immediately for: $messageToSpeak");
            _speakNextInQueue(); 
        }
    }).catchError((e) {
        if (mounted && !_isDisposed) {
            setState(() { _isCurrentlySpeaking = false; });
        } else if (!_isDisposed) {
            _isCurrentlySpeaking = false;
        }
        debugPrint("TTS speak error: $e");
        _speakNextInQueue();
    });
    debugPrint("🔊 TTS 재생 시도: $messageToSpeak (큐 남은 개수: ${_ttsQueue.length})");
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
                  if (mounted) Navigator.of(context).pop();
                },
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
    // 이 함수는 TTS 큐잉 시스템 도입으로 인해 현재 직접 사용되지 않음.
    // 필요하다면 큐에 메시지를 추가하는 빈도를 조절하는 데 사용할 수 있음.
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
    
    // 쿨다운: _lastGuidanceTime은 마지막으로 "큐에 성공적으로 메시지를 추가한 시간"으로 간주
    if (_lastGuidanceTime != null &&
        now.difference(_lastGuidanceTime!).inMilliseconds < 1500) { // 1.5초 쿨다운
      debugPrint("⏳ TTS 쿨다운 중 - 메시지 추가 건너뜀 (마지막 안내 시도: $_lastGuidanceTime)");
      return;
    }

    bool voiceEnabled = await isVoiceGuideEnabled();
    if (!voiceEnabled) {
      debugPrint("🔇 음성 안내 비활성화됨 - 안내 생략");
      return;
    }

    String sizeDesc = objectInfo.sizeDescription;
    String positionDesc = objectInfo.positionalDescription;


    String message = "$positionDesc에"; 
    if (sizeDesc.isNotEmpty) {
      message += " $sizeDesc 크기의";
    }
    message += " 장애물이 있습니다. 주의하세요."; 


    // 이전 메시지와 동일한 내용이면 큐에 추가하지 않음 (버벅거림 감소 효과)
    if (_lastEnqueuedMessage == message && _ttsQueue.isNotEmpty) {
        // 다만, 현재 말하고 있지 않고 큐도 비어있다면 동일 메시지라도 재생 시도할 수 있도록 함
        if (_isCurrentlySpeaking || _ttsQueue.contains(message)) {
             debugPrint("🔁 동일 메시지 반복으로 큐 추가 건너뜀: $message");
             return;
        }
    }
    
    debugPrint("➕ TTS 큐 추가 요청: $message");
    _addToTtsQueue(message); 
    _lastGuidanceTime = DateTime.now(); 
  }

  void onStepCount(StepCount event) async {
    if (_isDisposed || !mounted) return;

    // ... (이하 onStepCount 로직은 이전과 동일하게 유지)
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
    // UI 관련 코드는 이전과 동일하므로 생략 후, 기존 코드 유지
    // ... (이전 답변의 build 메서드 내용과 동일) ...
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
            right: 10,
            child: Transform.scale(
              scale: 1.5,
              alignment: Alignment.topRight,
              child: Container(
                width: 140,
                padding: const EdgeInsets.symmetric(
                    vertical: 10.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      spreadRadius: 1,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _isMoving ? '🚶 보행 중' : '🛑 정지 상태',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_steps 걸음',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('평균 속도',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                    Text(
                      '${getAverageSpeed().toStringAsFixed(2)} m/s',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.lightGreenAccent,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    const Text('실시간 속도',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                    Text(
                      '${getRealTimeSpeed().toStringAsFixed(2)} m/s',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
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
    _isDisposed = true;
    print("StepCounterPage dispose initiated");

    _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _checkTimer?.cancel();
    _checkTimer = null;

    flutterTts.stop();
    _ttsQueue.clear();
    _isCurrentlySpeaking = false;
    _lastEnqueuedMessage = null;


    _setPortraitOrientation();

    super.dispose();
    print("StepCounterPage disposed successfully");
  }
}
