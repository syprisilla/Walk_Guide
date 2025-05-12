import 'package:flutter/material.dart';

class FAQPage extends StatelessWidget {
  const FAQPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('앱이 아무 말도 하지 않아요.'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('음성 안내 설정을 확인하세요.'))],
          ),
          ExpansionTile(
            title: Text('데이터가 초기화됐어요.'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('로그인 계정을 확인해주세요.'))],
          ),
          ExpansionTile(
            title: Text('앱이 갑자기 종료돼요.'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('앱을 최신 버전으로 업데이트해주세요.'))],
          ),
          ExpansionTile(
            title: Text('피드백을 보내고 싶어요.'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('문의하기를 이용해주세요.'))],
          ),
        ],
      ),
    );
  }
}
