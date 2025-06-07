import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:walk_guide/main_page.dart';
import 'package:walk_guide/login_page.dart';
import 'package:walk_guide/nickname_input_page.dart';
import 'package:camera/camera.dart';

class SplashScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SplashScreen({super.key, required this.cameras});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    await Future.delayed(const Duration(seconds: 3)); // 로고 3초 표시

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 로그인 안 되어 있음
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final nickname = doc.data()?['nickname'];

      if (nickname == null || nickname.toString().trim().isEmpty) {
        // 닉네임이 없으면 입력 페이지로
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NicknameInputPage()),
        );
      } else {
        // 닉네임 있으면 메인 페이지로
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainScreen(cameras: widget.cameras),
          ),
        );
      }
    } catch (e) {
      print('🔥 Firestore 접근 오류: $e');
      // 오류 발생 시 로그인 페이지로 되돌리기
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(243, 244, 195, 35), // 노란 배경색
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo1.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 16),
            const Text(
              'WalkGuide',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
