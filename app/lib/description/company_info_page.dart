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

Widget buildContributor({
  required String name,
  required String role,
  required String githubUrl,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_circle, size: 40, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '역할: $role',
          style: const TextStyle(fontSize: 17, height: 1.5),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 15, color: Colors.black),
            children: [
              const TextSpan(text: 'Github 주소: '),
              TextSpan(
                text: githubUrl,
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse(githubUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
            ],
          ),
        ),
      ],
    ),
  );
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
    if (!enabled) return;

    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);

    await _flutterTts.speak('앱 제작자 소개 페이지입니다. 충북대학교 컴퓨터공학과. 팀명 S.CORE.');

    await _flutterTts.speak('김병우. 바운더리 박스 구현, 객체 감지 정확성 향상 및 버그 수정을 담당했습니다.');
    await _flutterTts.speak('권오섭. 카메라 초기설정, 엠엘 킷 기반 객체 감지 로직 구현을 담당했습니다.');
    await _flutterTts.speak('전수영. 로그인과 회원가입 기능, 앱 전체 UI 구성을 맡았습니다.');
    await _flutterTts.speak('김선영. 보행자 속도 분석 기능과 앱 음성 안내 기능을 담당했습니다.');
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
          const Text(
            '충북대학교 컴퓨터공학과',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text('팀명: S.CORE', style: TextStyle(fontSize: 16)),
          const Divider(height: 32),
          buildContributor(
            name: '김병우',
            role: '바운더리 박스 구현, 객체 감지 정확성 향상 및 버그 수정',
            githubUrl: 'https://github.com/xnoa03',
          ),
          buildContributor(
            name: '권오섭',
            role: '카메라 초기설정, ML Kit 기반 객체 감지 로직 구현',
            githubUrl: 'https://github.com/kos6490',
          ),
          buildContributor(
            name: '전수영',
            role: '로그인과 회원가입 기능 담당, 앱 전체 UI 구성',
            githubUrl: 'https://github.com/Jeonsooyoung',
          ),
          buildContributor(
            name: '김선영',
            role: '보행자 속도 분석 기능 담당, 앱 음성 안내 기능 담당',
            githubUrl: 'https://github.com/syprisilla',
          ),
        ],
      ),
    );
  }
}
