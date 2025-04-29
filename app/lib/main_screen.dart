import 'package:flutter/material.dart';
import 'package:walk_guide/step_counter_page.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘도 즐거운 하루 되세요!'),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                color: Colors.grey[300],
                child: const Center(
                  child: Text('지도', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
          BottomNavigationBar(
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.info_outline),
                label: '설명창',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.directions_walk),
                label: '보행시작하기',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings), // 또는 빈 아이콘 가능
                label: '',
              ),
            ],
            onTap: (index) {
              if (index == 0) {
                // 설명창 페이지로 이동 (임시)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('설명창으로 이동')));
              } else if (index == 1) {
                // 보행시작 페이지로 이동
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StepCounterPage(),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
