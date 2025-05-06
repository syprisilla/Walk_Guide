import 'package:flutter/material.dart';

class DescriptionPage extends StatelessWidget {
  final List<String> titles = [
    '계정 정보',
    '개인정보처리방침',
    '이용 약관',
    '사업자 정보',
    '오픈 소스 라이브러리',
    '앱 업데이트',
  ];

  final List<VoidCallback> actions = [
    () {}, // 계정 정보
    () {}, // 개인정보처리방침
    () {}, // 이용 약관
    () {}, // 사업자 정보
    () {}, // 오픈 소스
    () {}, // 앱 업데이트
  ];

  DescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('소개', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: titles.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(titles[index]),
            trailing: Icon(Icons.chevron_right),
            onTap: actions[index],
          );
        },
      ),
    );
  }
}
