import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';

class TechnologyPage extends StatefulWidget {
  const TechnologyPage({super.key});

  @override
  State<TechnologyPage> createState() => _TechnologyPageState();
}

class _TechnologyPageState extends State<TechnologyPage> {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _speakIfEnabled(String title, String detail) async {
    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      final String fullText = "$title. $detail";
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(fullText);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지 나갈 때 음성 안내 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('사용된 기술 및 기능'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          ExpansionTile(
            title: const Text(
              '센서 사용',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("센서 사용",
                    "sensors_plus 패키지를 활용해 스마트폰의 가속도 센서를 통해 사용자의 움직임을 감지합니다.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'sensors_plus 패키지를 활용해 스마트폰의 가속도 센서를 통해 사용자의 움직임을 감지합니다.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              'AI 기반 안내',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("AI 기반 안내",
                    "사용자의 걸음 수와 이동 시간을 기반으로 보행 속도를 계산하고, 이를 지속적으로 학습하여 개인 맞춤형 보행 패턴을 생성합니다.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    '사용자의 걸음 수와 이동 시간을 기반으로 보행 속도를 계산하고, 이를 지속적으로 학습하여 개인 맞춤형 보행 패턴을 생성합니다.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '음성 안내',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("음성 안내",
                    "Flutter TTS를 활용해 시각장애인이 시각 정보 없이도 상황을 인식할 수 있도록 실시간으로 음성 안내를 제공합니다.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'Flutter TTS를 활용해 시각장애인이 시각 정보 없이도 상황을 인식할 수 있도록 실시간으로 음성 안내를 제공합니다.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '로컬 저장소 Hive',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("로컬 저장소 Hive",
                    "Hive를 사용해 로컬에 보행 데이터를 저장합니다. 앱을 종료하거나 스마트폰을 껐다 켜도 이전 데이터를 복원합니다.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'Hive를 사용해 로컬에 보행 데이터를 저장합니다. 앱을 종료하거나 스마트폰을 껐다 켜도 이전 데이터를 복원합니다.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
