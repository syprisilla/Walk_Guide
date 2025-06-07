import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walk_guide/services/voice_guide_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({}); // 초기화
  });

  test('setVoiceGuideEnabled & isVoiceGuideEnabled 테스트', () async {
    expect(await isVoiceGuideEnabled(), true); // 기본값 true

    await setVoiceGuideEnabled(false);
    expect(await isVoiceGuideEnabled(), false);

    await setVoiceGuideEnabled(true);
    expect(await isVoiceGuideEnabled(), true);
  });

  test('setNavigationVoiceEnabled & isNavigationVoiceEnabled 테스트', () async {
    expect(await isNavigationVoiceEnabled(), true); // 기본값 true

    await setNavigationVoiceEnabled(false);
    expect(await isNavigationVoiceEnabled(), false);

    await setNavigationVoiceEnabled(true);
    expect(await isNavigationVoiceEnabled(), true);
  });
}
