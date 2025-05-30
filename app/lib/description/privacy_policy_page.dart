import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  List<Map<String, dynamic>> walkingData = [];

  @override
  void initState() {
    super.initState();
    fetchWalkingData();
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

  // 🔽 테스트 데이터 블록 시작
  Future<void> insertDummyWalkingData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final now = DateTime.now();

    for (int i = 0; i < 7; i++) {
      final fakeSpeed = 0.9 + i * 0.1; // 0.9 ~ 1.5 m/s
      final date = now.subtract(Duration(days: i));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('walking_data')
          .add({
            'speed': fakeSpeed,
            'timestamp': Timestamp.fromDate(date),
          });
    }

    await fetchWalkingData();
  }
  // 🔼 테스트 데이터 블록 끝

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

            // 🔽 테스트 데이터 블록 시작
            ElevatedButton(
              onPressed: insertDummyWalkingData,
              child: const Text("테스트용 더미 데이터 삽입"),
            ),
            const SizedBox(height: 12),
            // 🔼 테스트 데이터 블록 끝

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
