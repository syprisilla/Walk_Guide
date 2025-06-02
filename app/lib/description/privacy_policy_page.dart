import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _readContentIfEnabled();
  }

  Future<void> _readContentIfEnabled() async {
    final enabled = await isNavigationVoiceEnabled();
    if (!enabled) return;

    const String fullText = '''
보행 데이터 관리 페이지입니다.

첫째, 데이터 저장 위치.
모든 보행 데이터는 로컬 Hive에 안전하게 저장됩니다.

둘째, 백업 및 복원.
JSON 파일로 백업 및 복원이 가능합니다.
''';

    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(fullText);
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지 나갈 때 음성 안내 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보행 데이터 관리'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ListTile(
            leading: Icon(Icons.storage_outlined, size: 30),
            title: Text('데이터 저장 위치'),
            subtitle: Text('모든 보행 데이터는 로컬(Hive)에 안전하게 저장됩니다.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup_outlined, size: 30),
            title: Text('백업 및 복원'),
            subtitle: Text('JSON 파일로 백업/복원이 가능합니다.'),
          ),
        ],
      ),
    );
  }
}
