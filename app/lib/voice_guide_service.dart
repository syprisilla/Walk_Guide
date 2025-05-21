import 'package:shared_preferences/shared_preferences.dart';

Future<void> setVoiceGuideEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('voice_guide_enabled', enabled);
}

Future<bool> isVoiceGuideEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('voice_guide_enabled') ?? true;
}
