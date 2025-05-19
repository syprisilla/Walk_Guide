import 'package:flutter/material.dart';

class TechnologyPage extends StatelessWidget {
  const TechnologyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사용된 기술 및 기능')),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('센서 사용'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('sensors_plus 사용'))],
          ),
          ExpansionTile(
            title: Text('AI 기반 안내'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('보행 속도 학습'))],
          ),
          ExpansionTile(
            title: Text('음성 안내'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('Flutter TTS 사용'))],
          ),
          ExpansionTile(
            title: Text('로컬 저장소 Hive'),
            children: [Padding(padding: EdgeInsets.all(8), child: Text('데이터 저장 및 복원'))],
          ),
        ],
      ),
    );
  }
}
