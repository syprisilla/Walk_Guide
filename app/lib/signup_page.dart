import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _speak("이메일을 입력해주세요.");
      }
    });

    _passwordFocus.addListener(() {
      if (_passwordFocus.hasFocus) {
        _speak("비밀번호를 입력해주세요.");
      }
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    emailController.dispose();
    passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(text);
  }

  void _signUp() async {
    _speak("회원가입을 진행합니다.");

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _speak("이메일과 비밀번호를 입력해주세요.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 입력해주세요')),
      );
      return;
    }

    final authService = AuthService();
    await authService.signUpWithEmail(email, password, context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('회원가입'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              focusNode: _emailFocus,
              decoration: InputDecoration(
                hintText: '이메일',
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              focusNode: _passwordFocus,
              decoration: InputDecoration(
                hintText: '비밀번호',
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              style: const TextStyle(color: Colors.black),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(243, 244, 195, 35),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _signUp,
              child: const Text('회원가입'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
