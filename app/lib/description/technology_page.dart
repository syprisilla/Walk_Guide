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
      appBar: AppBar(title: const Text('사용된 기술 및 기능')),
      body: ListView(
        children: [
          ExpansionTile(
            title: const Text('센서 사용'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("센서 사용", "sensors_plus 사용");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('sensors_plus 사용'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('AI 기반 안내'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("AI 기반 안내", "보행 속도 학습");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('보행 속도 학습'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('음성 안내'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("음성 안내", "Flutter TTS 사용");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Flutter TTS 사용'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('로컬 저장소 Hive'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("로컬 저장소 Hive", "데이터 저장 및 복원");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('데이터 저장 및 복원'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
