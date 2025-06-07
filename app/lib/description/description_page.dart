import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/services/voice_guide_service.dart'; // 추가
import 'account_info_page.dart';
import 'privacy_policy_page.dart';
import 'app_guide_page.dart';
import 'company_info_page.dart';
import 'technology_page.dart';
import 'faq_page.dart';

class DescriptionPage extends StatefulWidget {
  const DescriptionPage({super.key});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  String? nickname;
  final FlutterTts _flutterTts = FlutterTts();

  final List<_DescriptionItem> items = [
    _DescriptionItem('보행 데이터 관리', PrivacyPolicyPage()),
    _DescriptionItem('앱 사용법', AppGuidePage()),
    _DescriptionItem('앱 제작자 소개', CompanyInfoPage()),
    _DescriptionItem('사용된 기술 및 기능', TechnologyPage()),
    _DescriptionItem('자주 묻는 질문', FAQPage()),
  ];

  @override
  void initState() {
    super.initState();
    fetchNickname();
  }

  Future<void> fetchNickname() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        nickname = doc.data()?['nickname'] ?? '사용자';
      });
    }
  }

  Future<void> _speakIfEnabled(String text) async {
    final enabled = await isNavigationVoiceEnabled(); // 설정 불러오기
    if (enabled) {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('소개'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                await _speakIfEnabled("계정 정보를 확인하는 페이지로 이동합니다."); // 조건부 음성 안내
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountInfoPage()),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/profile.jpg'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: nickname ?? '...',
                          style: const TextStyle(
                              fontSize: 25, fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(
                          text: '님',
                          style: TextStyle(fontSize: 25),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: GestureDetector(
                    onTap: () async {
                      await _speakIfEnabled(
                          "${item.title} 페이지로 이동합니다."); // 조건부 음성 안내
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => item.page),
                      );
                    },
                    child: Text(
                      item.title,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _DescriptionItem {
  final String title;
  final Widget page;

  _DescriptionItem(this.title, this.page);
}
