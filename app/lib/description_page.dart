import 'package:flutter/material.dart';

class DescriptionPage extends StatelessWidget {
  const DescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('앱 사용 설명'),
        backgroundColor: Colors.amber,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: const Text(
          '이 앱은 시각장애인을 위한 보행 보조 앱입니다.\n\n'
          '- 보행 시작하기 버튼을 눌러 측정을 시작하세요.\n'
          '- 지도에는 현재 위치 및 주변 정보가 표시될 예정입니다.\n'
          '- 향후 경로 안내, 음성 피드백 기능도 제공될 예정입니다.',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
