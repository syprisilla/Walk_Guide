import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';

class AppGuidePage extends StatefulWidget {
  const AppGuidePage({super.key});

  @override
  State<AppGuidePage> createState() => _AppGuidePageState();
}

class _AppGuidePageState extends State<AppGuidePage> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _speakIntroIfEnabled();
  }

  Future<void> _speakIntroIfEnabled() async {
    final enabled = await isNavigationVoiceEnabled();
    if (!enabled) return;

    final String fullText = '''
앱 사용법 페이지입니다.
WalkGuide 앱에 오신 것을 환영합니다.
WalkGuide는 시각장애인의 안전한 보행을 돕기 위해 설계된 앱입니다.
이 앱을 통해 실시간 안내와 보행 분석 기능을 제공합니다.

첫째, 실시간 안내 기능입니다.
음성 안내 제공, 장애물 경고, AI 피드백을 제공합니다.

둘째, 보행 데이터 분석입니다.
걸음 수, 속도, 정지 구간을 시각화하며
데이터 백업 및 복원 기능도 지원합니다.
''';

    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(fullText);
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지를 벗어날 때 음성 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('앱 사용법'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: const [
            Text('WalkGuide 앱에 오신 것을 환영합니다!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Divider(height: 24, thickness: 1.2),
            Text(
              'WalkGuide는 시각장애인의 안전한 보행을 돕기 위해 설계된 앱입니다.\n'
              '이 앱을 통해 실시간 안내와 보행 분석 기능을 제공합니다.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 24),
            Text('1. 실시간 안내 기능',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            SizedBox(height: 6),
            Text('- 음성 안내 제공\n- 장애물 경고\n- AI 피드백'),
            SizedBox(height: 24),
            Text('2. 보행 데이터 분석',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            SizedBox(height: 6),
            Text('- 걸음 수, 속도, 정지 구간 시각화\n- 데이터 백업 및 복원'),
          ],
        ),
      ),
    );
  }
}
