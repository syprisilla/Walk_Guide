import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';

class FAQPage extends StatefulWidget {
  const FAQPage({super.key});

  @override
  State<FAQPage> createState() => _FAQPageState();
}

class _FAQPageState extends State<FAQPage> {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _speakIfEnabled(String text) async {
    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: ListView(
        children: [
          ExpansionTile(
            title: const Text('앱이 아무 말도 하지 않아요.'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("앱이 아무 말도 하지 않아요. 음성 안내 설정을 확인하세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('음성 안내 설정을 확인하세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('데이터가 초기화됐어요.'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("데이터가 초기화됐어요. 로그인 계정을 확인해주세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('로그인 계정을 확인해주세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('앱이 갑자기 종료돼요.'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("앱이 갑자기 종료돼요. 앱을 최신 버전으로 업데이트해주세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('앱을 최신 버전으로 업데이트해주세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('피드백을 보내고 싶어요.'),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled("피드백을 보내고 싶어요. 문의하기를 이용해주세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('문의하기를 이용해주세요.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
