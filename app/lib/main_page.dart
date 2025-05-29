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
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MainScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainScreen({super.key, required this.cameras});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double Function()? _getSpeed;
  final FlutterTts _flutterTts = FlutterTts();
  LatLng? _currentLocation;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadNicknameAndGreet();
    _getCurrentLocation();
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
      print("\uB2C9\uB124\uC784 \uBD88\uB7EC\uC624\uAE30 \uC2E4\uD328: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();
    final newLocation = LatLng(position.latitude, position.longitude);

    setState(() {
      _currentLocation = newLocation;
    });

    _mapController.move(newLocation, 16.0);
  }

  Future<void> _speakWelcome(String nickname) async {
    final message = getTimeBasedWelcomeMessage(nickname);
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);
  }

  String getTimeBasedWelcomeMessage(String nickname) {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "$nickname\uB2D8, \uC88B\uC740 \uC544\uCE68\uC785\uB2C8\uB2E4. \uC624\uB298\uB3C4 \uC548\uC804\uD558\uAC8C \uBCF4\uD5D8 \uB3C4\uC6C0\uC744 \uB4DC\uB9AC\uACA0\uC5B4\uC694.";
    } else if (hour < 18) {
      return "$nickname\uB2D8, \uC88B\uC740 \uC624\uD6C4\uC785\uB2C8\uB2E4. \uC624\uB298\uB3C4 \uD568\uAED8 \uAC78\uC5B4\uC694.";
    } else {
      return "$nickname\uB2D8, \uC88B\uC740 \uC800\uB141\uC785\uB2C8\uB2E4. \uC870\uC2EC\uD574\uC11C \uB2E4\uB140\uC624\uC138\uC694.";
    }
  }

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
        body: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation ?? LatLng(37.5665, 126.9780),
            initialZoom: 15.0,
            minZoom: 3.0, // 최소 축소 제한
            maxZoom: 18.0, // 최대 확대 제한
            maxBounds: LatLngBounds(
              LatLng(-85.0, -180.0), // 남서쪽 경계
              LatLng(85.0, 180.0), // 북동쪽 경계
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.oss.walk_guide',
              tileProvider: NetworkTileProvider(),
              tileSize: 256,
              retinaMode: true,
              backgroundColor: Colors.white,
            ),
            if (_currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation!,
                    width: 50,
                    height: 50,
                    child: const Icon(
                      Icons.directions_walk,
                      size: 40,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
          ],
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
