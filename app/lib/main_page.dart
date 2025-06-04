// File: lib/main_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final FocusNode _walkStartFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    print("MainScreen initState 들어옴");
    _setPortraitOrientation(); // Ensure portrait on init
    _loadNicknameAndGreet();
    _getCurrentLocation();

    _walkStartFocusNode.addListener(() async {
      final enabled = await isNavigationVoiceEnabled();
      if (_walkStartFocusNode.hasFocus && enabled && mounted) {
        _flutterTts.speak("보행을 시작하려면 이 버튼을 누르세요.");
      }
    });
  }

  Future<void> _setPortraitOrientation() async {
    print("MainScreen: Setting orientation to Portrait");
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _setLandscapeOrientation() async {
    print("MainScreen: Setting orientation to Landscape");
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }


  @override
  void dispose() {
    _flutterTts.stop();
    _walkStartFocusNode.dispose();
    print("MainScreen disposed");
    super.dispose();
  }

  Future<void> _loadNicknameAndGreet() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final enabled = await isVoiceGuideEnabled();
        if (doc.exists && enabled && mounted) {
          final nickname = doc['nickname'];
          _speakWelcome(nickname);
        }
      }
    } catch (e) {
      print("닉네임 불러오기 실패: $e");
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

    try {
      Position position = await Geolocator.getCurrentPosition();
      final newLocation = LatLng(position.latitude, position.longitude);

      if (mounted) {
          setState(() {
            _currentLocation = newLocation;
          });
           _mapController.move(newLocation, 16.0);
      }
    } catch (e) {
        print("위치 가져오기 실패: $e");
        if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('현재 위치를 가져오는 데 실패했습니다.'))
            );
        }
    }
  }

  Future<void> _speakWelcome(String nickname) async {
    final message = getTimeBasedWelcomeMessage(nickname);
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(message);
  }

  String getTimeBasedWelcomeMessage(String nickname) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final second = now.second;

    final isMorning =
        (hour > 4 || (hour == 4 && (minute > 0 || second > 0))) && hour < 12;
    final isAfternoon = (hour >= 12 && hour < 18);

    if (isMorning) {
      return "$nickname님, 좋은 아침입니다. 오늘도 안전한 보행 도움 드릴게요.";
    } else if (isAfternoon) {
      return "$nickname님, 좋은 오후입니다. 오늘도 함께 걸어요.";
    } else {
      return "$nickname님, 좋은 저녁입니다. 조심해서 다녀오세요.";
    }
  }

  @override
  Widget build(BuildContext context) {
    print("MainScreen build 들어옴. Ensuring portrait orientation.");
    _setPortraitOrientation();

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
              onPressed: () async {
                final enabled = await isNavigationVoiceEnabled();
                if (enabled && mounted) {
                  await _flutterTts.setLanguage("ko-KR");
                  await _flutterTts.setSpeechRate(0.5);
                  await _flutterTts.speak("관리 페이지로 이동합니다.");
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DescriptionPage(),
                  ),
                ).then((_) async {
                   if (mounted) await _flutterTts.stop();
                });
              },
            ),
          ],
        ),
        body: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation ?? LatLng(37.5665, 126.9780),
            initialZoom: 15.0,
            minZoom: 3.0,
            maxZoom: 18.0,
            maxBounds: LatLngBounds(
              LatLng(-85.0, -180.0),
              LatLng(85.0, 180.0),
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
                    child: Image.asset(
                      'assets/images/walkingIcon.png',
                      width: 50,
                      height: 50,
                    ),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.grey.withOpacity(0.6),
          elevation: 0,
          child: const Icon(Icons.my_location,
              color: Color.fromARGB(255, 254, 255, 255)),
          onPressed: () {
            if (_currentLocation != null) {
              _mapController.move(_currentLocation!, 16.0);
            } else {
              if(mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')),
                );
              }
            }
          },
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black54,
          unselectedItemColor: Colors.black54,
          selectedFontSize: 16,
          unselectedFontSize: 14,
          iconSize: 32,
          items: [
            BottomNavigationBarItem(
              icon: Focus(
                focusNode: _walkStartFocusNode,
                child: const Icon(Icons.directions_walk),
              ),
              label: '보행시작하기',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: '분석',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: '설정',
            ),
          ],
          onTap: (index) async {
            final navigationVoiceEnabled = await isNavigationVoiceEnabled();

            if (index == 0) {
              if (widget.cameras.isEmpty) {
                 if(mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('사용 가능한 카메라가 없습니다.')),
                    );
                 }
                return;
              }

              await _setLandscapeOrientation();

              if (navigationVoiceEnabled && mounted) {
                await _flutterTts.speak("보행을 시작합니다.");
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
              ).then((_) {
                print("Returned from StepCounterPage. Ensuring portrait orientation in MainScreen.");
                _setPortraitOrientation();
              });
            } else if (index == 1) {
              if (navigationVoiceEnabled && mounted) {
                await _flutterTts.speak("분석 페이지로 이동합니다.");
              }
              await _setPortraitOrientation(); // Ensure portrait before navigating
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AnalyticsDashboardPage(),
                ),
              ).then((_) => _setPortraitOrientation());
            } else if (index == 2) {
              if (navigationVoiceEnabled && mounted) {
                await _flutterTts.speak("설정 페이지로 이동합니다.");
              }
              await _setPortraitOrientation(); // Ensure portrait before navigating
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              ).then((_) => _setPortraitOrientation());
            }
          },
        ),
      ),
    );
  }
}