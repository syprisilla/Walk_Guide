import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:walk_guide/splash_page.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 이메일/비밀번호 로그인 함수
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      print('로그인 실패: ${e.code} - ${e.message}');
      return null;
    }
  }
}
  // 로그아웃 함수 (선택)
Future<void> signOut(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const SplashScreen()),
    (Route<dynamic> route) => false, // 이전 화면 모두 제거
  );
}