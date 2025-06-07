import 'package:flutter/material.dart';
import 'package:walk_guide/models/walk_session.dart';

class SessionDetailPage extends StatelessWidget {
  final WalkSession session;

  const SessionDetailPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📋 세션 상세 정보')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('시작 시간: ${session.startTime}'),
            Text('종료 시간: ${session.endTime}'),
            Text('걸음 수: ${session.stepCount}'),
            Text('평균 속도: ${session.averageSpeed.toStringAsFixed(2)} m/s'),
          ],
        ),
      ),
    );
  }
}
