import 'package:flutter/material.dart';
import 'package:walk_guide/main_screen.dart';

// 시작 화면 (로딩 화면)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
 State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 3초 후에 MainScreen으로 이동
    Future.delayed(Duration(seconds: 10), () {
      Navigator.pushReplacement(
        // ignore: use_build_context_synchronously
        context,
        MaterialPageRoute(builder: (context) => MainScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(243, 244, 195, 35), // 노란 배경색 설정
      body: Center(
        child: Image.asset(
        'assets/images/logo1.png',
        width: 100, // 원하는 크기로 조절
        height: 100,
        ),
      ),
    );
  }
}