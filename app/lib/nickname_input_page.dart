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

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (nickname.isEmpty || user == null) return;

    setState(() {
      _isSaving = true;
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': user.email,
      'nickname': nickname,
    });

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainScreen(cameras: camerasGlobal),
      ),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('닉네임 입력'),
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
    );
  }
}
