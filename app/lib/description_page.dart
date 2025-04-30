import 'package:flutter/material.dart';

class DescriptionPage extends StatelessWidget {
  const DescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300], 
      appBar: AppBar(
        title: const Text('무슨 기능이 있나요?'),
        backgroundColor: Colors.amber,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text(
              '• 지도 •',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('→ 사용자의 현재 위치와 주변 정보가 나타나요!',
            style: TextStyle(fontSize: 20),
            ),

            const SizedBox(height: 20),

            const Text(
              '• 객체 감지 •',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('→ 사용자 주변 객체를 탐지해요. 객체의 크기를 알고 정의할 수 있어요.',
            style: TextStyle(fontSize: 20),
            ),

            const SizedBox(height: 20),

            const Text(
              '• 음성 안내 •',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('→ 사용자의 보행 속도를 ai가 파악하고 안내해요. 음성 피드백을 제공해요.',
            style: TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}