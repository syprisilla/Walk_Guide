import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보행 데이터 관리'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ListTile(
            leading: Icon(Icons.storage_outlined, size: 30),
            title: Text('데이터 저장 위치'),
            subtitle: Text('모든 보행 데이터는 로컬(Hive)에 안전하게 저장됩니다.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup_outlined, size: 30),
            title: Text('백업 및 복원'),
            subtitle: Text('JSON 파일로 백업/복원이 가능합니다.'),
          ),
        ],
      ),
    );
  }
}
