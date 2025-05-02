import 'package:flutter/material.dart';

class AnalyticsDashboardPage extends StatelessWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 보행 데이터 분석'),
        backgroundColor: Colors.amber,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '실시간 속도 그래프',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 120, child: Center(child: Text('📈 여기에 그래프 표시'))),
            SizedBox(height: 16),

            Text(
              '최근 일주일 평균 속도 변화',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 120, child: Center(child: Text('📅 여기에 그래프 표시'))),
            SizedBox(height: 16),

            Text(
              '세션 다시보기',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 80, child: Center(child: Text('🔁 세션 리스트'))),
            SizedBox(height: 16),

            Text(
              '데이터 초기화 및 백업',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                ElevatedButton(onPressed: null, child: Text('초기화')),
                SizedBox(width: 10),
                ElevatedButton(onPressed: null, child: Text('백업')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
