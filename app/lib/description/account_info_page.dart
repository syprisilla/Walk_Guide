import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/services/auth_service.dart';
import 'package:walk_guide/voice_guide_service.dart';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  String? nickname;
  String? email;
  String? loginMethod;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    // 페이지가 그려진 후에 사용자 정보 로드 + 음성 재생
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchUserInfo();
    });
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지 벗어날 때 음성 정지
    super.dispose();
  }

  Future<void> fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        nickname = doc.data()?['nickname'] ?? '사용자';
        email = user.email;
        loginMethod = user.providerData.first.providerId == 'password'
            ? '이메일 로그인'
            : 'Google 로그인';
      });

      final enabled = await isNavigationVoiceEnabled();
      if (enabled && mounted) {
        final speakableEmail =
            (email ?? '').replaceAll('@', ' 골뱅이 ').replaceAll('.', ' 점 ');
        final message = "계정 정보를 확인하는 페이지입니다. "
            "이메일 주소는 $speakableEmail 입니다. "
            "로그인 방식은 $loginMethod 입니다.";

        await _flutterTts.setLanguage("ko-KR");
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.speak(message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('계정 정보'),
        backgroundColor: Colors.amber,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/profile.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  nickname != null ? '$nickname님' : '...',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (email != null)
              Text(
                '이메일: $email',
                style: const TextStyle(fontSize: 20, color: Colors.black),
              ),
            const SizedBox(height: 8),
            if (loginMethod != null)
              Text(
                '로그인 방식: $loginMethod',
                style: const TextStyle(fontSize: 20, color: Colors.black),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => AuthService().signOut(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '로그아웃',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
