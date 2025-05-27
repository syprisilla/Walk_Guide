import 'package:flutter/material.dart';
import 'package:walk_guide/step_counter_page.dart';
import 'package:walk_guide/description/description_page.dart';
import 'package:walk_guide/analytics_dashboard_page.dart';
import 'package:walk_guide/settings_page.dart';
import 'package:walk_guide/voice_guide_service.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainScreen({super.key, required this.cameras});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double Function()? _getSpeed;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    print("MainScreen initState 들어옴");
    _loadNicknameAndGreet();
  }

  Future<void> _loadNicknameAndGreet() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final enabled = await isVoiceGuideEnabled();

        if (doc.exists && enabled) {
          final nickname = doc['nickname'];
          _speakWelcome(nickname);
        }
      }
    } catch (e) {
      print("닉네임 불러오기 실패: $e");
    }
  }

  String getTimeBasedWelcomeMessage(String nickname) {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return "$nickname님, 좋은 아침입니다. 오늘도 안전하게 보행 도와드릴게요.";
    } else if (hour < 18) {
      return "$nickname님, 좋은 오후입니다. 오늘도 함께 걸어요.";
    } else {
      return "$nickname님, 좋은 저녁입니다. 조심해서 다녀오세요.";
    }
  }

  Future<void> _speakWelcome(String nickname) async {
    final message = getTimeBasedWelcomeMessage(nickname);
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);
  }

  @override
  Widget build(BuildContext context) {
    print("MainScreen initState 들어옴");
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('오늘도 즐거운 하루 되세요!'),
          centerTitle: true,
          backgroundColor: Colors.amber,
          actions: [
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '설명 보기',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DescriptionPage(),
                  ),
                );
              },
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[300],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text('지도', style: TextStyle(fontSize: 24)),
              SizedBox(height: 20),
            ],
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
              icon: Icon(Icons.bar_chart),
              label: '분석',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: '설정',
            ),
          ],
          onTap: (index) {
            if (index == 0) {
              if (widget.cameras.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('사용 가능한 카메라가 없습니다.')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StepCounterPage(
                    onInitialized: (double Function() fn) {
                      _getSpeed = fn;
                    },
                    cameras: widget.cameras,
                  ),
                ),
              );
            } else if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AnalyticsDashboardPage(),
                ),
              );
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
