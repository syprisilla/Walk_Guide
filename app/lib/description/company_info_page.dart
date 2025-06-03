import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart'; // 음성 안내 설정 확인용
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

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

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지 벗어나면 음성 출력 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('앱 제작자 소개'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          const Text('충북대학교',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('팀명: S.CORE', style: TextStyle(fontSize: 16)),
          const Divider(height: 32),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('김병우'),
            subtitle: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                    text: '바운더리 박스 구현, 객체 감지 정확성 향상 및 버그 수정\n',
                  ),
                  TextSpan(
                    text: 'https://github.com/xnoa03',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse('https://github.com/byeongwoo-kim'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('권오섭'),
            subtitle: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                    text: '카메라 초기설정, ML Kit 기반 객체 감지 로직 구현\n',
                  ),
                  TextSpan(
                    text: 'https://github.com/kos6490',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse('https://github.com/kos6490'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('전수영'),
            subtitle: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                    text: '로그인과 회원가입 기능 담당, 앱 전체 UI 구성\n',
                  ),
                  TextSpan(
                    text: 'https://github.com/Jeonsooyoung',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse('https://github.com/Jeonsooyoung'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('김선영'),
            subtitle: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                    text: 'AI 보행자 속도 분석 기능 담당, 앱 음성 안내 기능 담당\n',
                  ),
                  TextSpan(
                    text: 'https://github.com/syprisilla',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse('https://github.com/syprisilla'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ),
        ],
      ),
    );
  }
}
