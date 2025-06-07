import 'package:flutter/material.dart';
import 'package:walk_guide/services/voice_guide_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _voiceEnabled = true;
  bool _navigationVoiceEnabled = true; //  페이지 이동 음성 안내 여부

  @override
  void initState() {
    super.initState();
    _loadVoiceSetting();
  }

  Future<void> _loadVoiceSetting() async {
    final enabled = await isVoiceGuideEnabled();
    final navEnabled = await isNavigationVoiceEnabled(); // 따로 저장된 값 로드
    setState(() {
      _voiceEnabled = enabled;
      _navigationVoiceEnabled = navEnabled;
    });
  }

  Future<void> _toggleVoiceSetting(bool value) async {
    await setVoiceGuideEnabled(value);
    setState(() {
      _voiceEnabled = value;
    });
  }

  Future<void> _toggleNavigationVoiceSetting(bool value) async {
    await setNavigationVoiceEnabled(value); // 새로 추가될 저장 함수
    setState(() {
      _navigationVoiceEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.amber,
      ),
      backgroundColor: Colors.white,
      body: ListView(
        children: [
          SwitchListTile(
              title: const Text('음성 안내'),
              subtitle: const Text('앱 실행 시 음성 환영 메시지 재생'),
              value: _voiceEnabled,
              onChanged: _toggleVoiceSetting,
              activeColor: Colors.white,
              activeTrackColor: Colors.lightBlueAccent),
          SwitchListTile(
              title: const Text('페이지 이동 음성 안내'),
              subtitle: const Text('버튼 터치 시 목적지를 음성으로 알려줍니다'),
              value: _navigationVoiceEnabled,
              onChanged: _toggleNavigationVoiceSetting,
              activeColor: Colors.white,
              activeTrackColor: Colors.lightBlueAccent),
        ],
      ),
    );
  }
}
