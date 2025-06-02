import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:walk_guide/main_page.dart';
import 'package:walk_guide/main.dart';

class NicknameInputPage extends StatefulWidget {
  const NicknameInputPage({super.key});

  @override
  State<NicknameInputPage> createState() => _NicknameInputPageState();
}

class _NicknameInputPageState extends State<NicknameInputPage> {
  final _nicknameController = TextEditingController();
  bool _isSaving = false;

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
    }, SetOptions(merge: true)); // ← 덮어쓰기 방지

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
        SnackBar(content: Text('닉네임 저장에 실패했습니다. 다시 시도해주세요.')),
      );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  return PopScope(
    canPop: false, // 뒤로가기 동작 차단
    child: Scaffold(
      appBar: AppBar(
        title: const Text('닉네임 입력'),
        automaticallyImplyLeading: false,
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
              decoration: const InputDecoration(
                labelText: '닉네임',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveNickname,
                child: _isSaving
                    ? const CircularProgressIndicator()
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