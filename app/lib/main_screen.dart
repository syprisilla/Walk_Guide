import 'package:flutter/material.dart';
import 'package:walk_guide/step_counter_page.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('메인 화면'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '안녕하세요!',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                MaterialPageRoute(builder: (context) => const StepCounterPage());
              },
              child: Text('버튼'),
            ),
          ],
        ),
      ),
    );
  }
}