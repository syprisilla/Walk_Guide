import 'package:shared_preferences/shared_preferences.dart';

// ✅ 환영 음성 안내 설정
Future<void> setVoiceGuideEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('voice_guide_enabled', enabled);
}

Future<bool> isVoiceGuideEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('voice_guide_enabled') ?? true;
}

// 페이지 이동 음성 안내 설정
Future<void> setNavigationVoiceEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('navigation_voice_enabled', enabled);
}

Future<bool> isNavigationVoiceEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('navigation_voice_enabled') ?? true;
}
