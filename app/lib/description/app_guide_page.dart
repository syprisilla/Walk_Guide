import 'package:flutter/material.dart';

class AppGuidePage extends StatelessWidget {
  const AppGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 사용법')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: const [
            Text('WalkGuide 앱에 오신 것을 환영합니다!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Divider(height: 24, thickness: 1.2),
            Text(
              'WalkGuide는 시각장애인의 안전한 보행을 돕기 위해 설계된 앱입니다.\n'
              '이 앱을 통해 실시간 안내와 보행 분석 기능을 제공합니다.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 24),
            Text('1. 실시간 안내 기능', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            SizedBox(height: 6),
            Text('- 음성 안내 제공\n- 장애물 경고\n- AI 피드백'),
            SizedBox(height: 24),
            Text('2. 보행 데이터 분석', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            SizedBox(height: 6),
            Text('- 걸음 수, 속도, 정지 구간 시각화\n- 데이터 백업 및 복원'),
          ],
        ),
      ),
    );
  }
}
