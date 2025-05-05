import 'package:flutter/material.dart';
import 'package:walk_guide/step_counter_page.dart';
import 'package:walk_guide/description_page.dart';
import 'package:walk_guide/login_screen.dart';


class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
  child: Scaffold(
    appBar: AppBar(
      title: const Text('오늘도 즐거운 하루 되세요!'),
      centerTitle: true,
      backgroundColor: Colors.amber,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline,
             size: 28),
          tooltip: '설명 보기',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DescriptionPage()),
            );
          },
        ),
      ],
    ),
    body: Center(
      child: Container(
        color: Colors.grey[300],
         width: double.infinity,
         height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('지도', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text('로그인 화면으로 이동'),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: BottomNavigationBar(
      selectedFontSize: 16,
      unselectedFontSize: 14,
      iconSize: 32,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_walk),
          label: '보행시작하기',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '설정',
        ),
      ],
      onTap: (index) {
        if (index == 0) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DescriptionPage()),
          );
        } else if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StepCounterPage()),
          );
        } else if (index == 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('설정 페이지는 준비 중입니다')),
          );
        }
      },
    ),
  ),
);
}
}