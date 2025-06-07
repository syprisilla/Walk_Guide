import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:walk_guide/step_counter/real_time_speed_service.dart';
import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RealTimeSpeedService 테스트', () {
    setUpAll(() async {
      // 메모리 상에서 Hive 초기화
      final tempDir = Directory.systemTemp.createTempSync();
      Hive.init(tempDir.path);
      await Hive.openBox<DateTime>(RealTimeSpeedService.boxName);
    });

    tearDown(() async {
      final box = Hive.box<DateTime>(RealTimeSpeedService.boxName);
      await box.clear();
    });

    test('recordStep() 호출 시 Hive에 기록됨', () async {
      await RealTimeSpeedService.recordStep();
      final box = Hive.box<DateTime>(RealTimeSpeedService.boxName);
      expect(box.isNotEmpty, true);
    });

    test('getSpeed()는 기록된 데이터 기준으로 속도 반환', () async {
      await RealTimeSpeedService.recordStep(
          DateTime.now().subtract(Duration(seconds: 5)));
      final speed = RealTimeSpeedService.getSpeed();
      expect(speed, greaterThan(0));
    });

    test('getSpeed()는 유효 시간 밖 데이터일 경우 0 반환', () async {
      final box = Hive.box<DateTime>(RealTimeSpeedService.boxName);
      await box.clear();
      await box.add(DateTime.now().subtract(const Duration(seconds: 20)));
      final speed = RealTimeSpeedService.getSpeed();
      expect(speed, 0);
    });

    test('clear() 호출 시 Hive 비움 및 속도 초기화', () async {
      await RealTimeSpeedService.recordStep();
      expect(RealTimeSpeedService.hasRecentSteps, true);

      RealTimeSpeedService.clear(); // delay: false
      await Future.delayed(const Duration(milliseconds: 100)); // 비동기 대기

      final box = Hive.box<DateTime>(RealTimeSpeedService.boxName);
      expect(box.isEmpty, true);
      expect(RealTimeSpeedService.hasRecentSteps, false);
    });

    test('hasRecentSteps는 기록 유무에 따라 true/false 반환', () async {
      expect(RealTimeSpeedService.hasRecentSteps, false);
      await RealTimeSpeedService.recordStep();
      expect(RealTimeSpeedService.hasRecentSteps, true);
    });
  });
}
