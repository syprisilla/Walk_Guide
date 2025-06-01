import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, dynamic>> walkingData = [];

  @override
  void initState() {
    super.initState();
    _readContentIfEnabled();
    fetchWalkingData();
  }

  Future<void> _readContentIfEnabled() async {
    final enabled = await isNavigationVoiceEnabled();
    if (!enabled) return;

    const String fullText = '''
보행 데이터 관리 페이지입니다.

첫째, 데이터 저장 위치.
모든 보행 데이터는 로컬 Hive에 안전하게 저장됩니다.

둘째, 백업 및 복원.
JSON 파일로 백업 및 복원이 가능합니다.
''';

    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(fullText);
  }

  Future<void> fetchWalkingData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walking_data')
        .orderBy('timestamp', descending: true)
        .limit(7)
        .get();

    final data = snapshot.docs.map((doc) => doc.data()).toList();

    setState(() {
      walkingData = data;
    });
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지 나갈 때 음성 안내 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('보행 데이터 관리')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '최근 보행 속도 기록 (최근 7회)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: walkingData.isEmpty
                  ? const Center(child: Text("저장된 데이터가 없습니다."))
                  : ListView.builder(
                      itemCount: walkingData.length,
                      itemBuilder: (context, index) {
                        final data = walkingData[index];
                        final ts = (data['timestamp'] as Timestamp).toDate();
                        final speed = (data['speed'] ?? 0.0).toStringAsFixed(2);

                        return ListTile(
                          leading: const Icon(Icons.directions_walk),
                          title: Text('$speed m/s'),
                          subtitle: Text('${ts.toLocal()}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
