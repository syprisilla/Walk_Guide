import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import 'package:walk_guide/services/firestore_service.dart';

class RealTimeSpeedService {
  static const String boxName = 'recent_steps';
  static const Duration window = Duration(seconds: 12);
  static const Duration holdTime = Duration(seconds: 10);
  static const Duration clearDelay = Duration(seconds: 15); // 지연 삭제 시간

  static double _lastSpeed = 0.0;
  static DateTime? _lastUpdateTime;

  static Future<void> recordStep([DateTime? time]) async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<DateTime>(boxName);
      debugPrint("✅ Hive recent_steps 박스 열림 (recordStep 내부)");
    }

    final box = Hive.box<DateTime>(boxName);
    final timestamp = time ?? DateTime.now();
    box.add(timestamp);
    debugPrint("📌 recordStep 저장됨: $timestamp");
  }

  static double getSpeed() {
    if (!Hive.isBoxOpen(boxName)) {
      debugPrint("⚠️ getSpeed 호출 시 박스가 열려있지 않음");
      return 0.0;
    }

    final box = Hive.box<DateTime>(boxName);
    final now = DateTime.now();

    final validSteps = box.values
        .where((t) => now.difference(t).inSeconds <= window.inSeconds)
        .toList();

    final count = validSteps.length;
    final speed = count * 0.7 / window.inSeconds;

    if (speed > 0) {
      _lastSpeed = speed;
      _lastUpdateTime = now;
      return speed;
    }

    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inSeconds <= holdTime.inSeconds) {
      return _lastSpeed;
    }

    _lastSpeed = 0.0;
    return 0.0;
  }

  static void clear({bool delay = false}) {
    if (!Hive.isBoxOpen(boxName)) return;

    final box = Hive.box<DateTime>(boxName);

    if (delay) {
      Future.delayed(clearDelay, () async {
        //firestore에 속도 정보 저장
        if (_lastSpeed > 0.0) {
          await FirestoreService.saveWalkingSpeed(_lastSpeed);
        }
        box.clear();
        _lastSpeed = 0.0;
        _lastUpdateTime = null;
        debugPrint("🕒 recent_steps 지연 삭제됨");
      });
    } else {
      //firestore에 속도 정보 저장
      if (_lastSpeed > 0.0) {
        FirestoreService.saveWalkingSpeed(_lastSpeed);
      }
      box.clear();
      _lastSpeed = 0.0;
      _lastUpdateTime = null;
      debugPrint("🧹 recent_steps 즉시 삭제됨");
    }
  }

  static bool get hasRecentSteps {
    if (!Hive.isBoxOpen(boxName)) return false;

    final box = Hive.box<DateTime>(boxName);
    return box.isNotEmpty;
  }
}
