import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/main/main_page.dart';
import 'package:walk_guide/main.dart';
import 'package:walk_guide/services/voice_guide_service.dart';

class NicknameInputPage extends StatefulWidget {
  const NicknameInputPage({super.key});

  @override
  State<NicknameInputPage> createState() => _NicknameInputPageState();
}

class _NicknameInputPageState extends State<NicknameInputPage> {
  final _nicknameController = TextEditingController();
  final FocusNode _nicknameFocus = FocusNode();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 400), _speakIntroIfEnabled);
  }

  Future<void> _speakIntroIfEnabled() async {
    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.speak("닉네임 입력 페이지입니다. 사용할 닉네임을 입력해주세요.");
    }
  }

  Future<bool> isNicknameTaken(String nickname) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (nickname.isEmpty || user == null) return;

    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.speak("닉네임 저장 중입니다. 잠시만 기다려주세요.");
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final taken = await isNicknameTaken(nickname);
      if (taken) {
        setState(() {
          _isSaving = false;
        });

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('닉네임 중복'),
            content: const Text('이미 사용 중인 닉네임입니다. 다른 닉네임을 입력해주세요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'nickname': nickname,
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainScreen(cameras: camerasGlobal),
        ),
      );
    } catch (e) {
      debugPrint('🔥 닉네임 저장 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임 저장에 실패했습니다. 다시 시도해주세요.')),
        );
        final enabled = await isNavigationVoiceEnabled();
        if (enabled) {
          await _flutterTts.awaitSpeakCompletion(true);
          await _flutterTts.speak("닉네임 저장에 실패했습니다. 다시 시도해주세요.");
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _nicknameFocus.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('닉네임 입력'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '사용할 닉네임을 입력해주세요.',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nicknameController,
                focusNode: _nicknameFocus,
                decoration: InputDecoration(
                  hintText: '닉네임',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.black, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.black, width: 1.0),
                  ),
                ),
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(243, 244, 195, 35),
                    foregroundColor: Colors.black,
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveNickname,
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('저장하고 시작하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
