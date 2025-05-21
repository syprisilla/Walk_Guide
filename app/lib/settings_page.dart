import 'package:flutter/material.dart';
import 'package:walk_guide/voice_guide_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _voiceEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadVoiceSetting();
  }

  Future<void> _loadVoiceSetting() async {
    final enabled = await isVoiceGuideEnabled();
    setState(() {
      _voiceEnabled = enabled;
    });
  }

  Future<void> _toggleVoiceSetting(bool value) async {
    await setVoiceGuideEnabled(value);
    setState(() {
      _voiceEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.amber,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('음성 안내'),
            subtitle: const Text('앱 실행 시 음성 환영 메시지 재생'),
            value: _voiceEnabled,
            onChanged: _toggleVoiceSetting,
          ),
        ],
      ),
    );
  }
}
