import 'package:flutter/material.dart';

class CompanyInfoPage extends StatelessWidget {
  const CompanyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 제작자 소개')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: const [
          Text('충북대학교',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text('팀명: SCORE', style: TextStyle(fontSize: 16)),
          Divider(height: 32),
          ListTile(
              leading: Icon(Icons.person),
              title: Text('김병우'),
              subtitle: Text('바운더리 박스 구현, 객체 감지 정확성 향상 및 버그 수정')),
          ListTile(
              leading: Icon(Icons.person),
              title: Text('권오섭'),
              subtitle: Text('카메라 초기설정, ML Kit 기반 객체 감지 로직 구현')),
          ListTile(
              leading: Icon(Icons.person),
              title: Text('전수영'),
              subtitle: Text('~~~~~')),
          ListTile(
              leading: Icon(Icons.person),
              title: Text('김선영'),
              subtitle: Text('~~~~~')),
        ],
      ),
    );
  }
}
