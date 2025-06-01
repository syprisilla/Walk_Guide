import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart'; // 음성 안내 설정 확인용

class CompanyInfoPage extends StatefulWidget {
  const CompanyInfoPage({super.key});

  @override
  State<CompanyInfoPage> createState() => _CompanyInfoPageState();
}

class _CompanyInfoPageState extends State<CompanyInfoPage> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _speakIntroText(); // 페이지 진입 시 안내
  }

  Future<void> _speakIntroText() async {
    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      const text = '앱 제작자 소개 페이지입니다. 충북대학교. 팀명 SCORE. 김병우, 권오섭, 전수영, 김선영';
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 제작자 소개')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: const [
          Text('충북대학교',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text('팀명: SCORE', style: TextStyle(fontSize: 16)),
          Divider(height: 32),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('김병우'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('권오섭'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('전수영'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('김선영'),
            subtitle: Text('~~~~~'),
          ),
        ],
      ),
    );
  }
}
