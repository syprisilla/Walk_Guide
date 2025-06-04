import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:walk_guide/voice_guide_service.dart';

class FAQPage extends StatefulWidget {
  const FAQPage({super.key});

  @override
  State<FAQPage> createState() => _FAQPageState();
}

class _FAQPageState extends State<FAQPage> {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _speakIfEnabled(String text) async {
    final enabled = await isNavigationVoiceEnabled();
    if (enabled) {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop(); // 페이지를 벗어날 때 음성 중지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('자주 묻는 질문'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          ExpansionTile(
            title: const Text(
              '앱이 아무 말도 하지 않아요.',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled(
                    "앱이 아무 말도 하지 않아요. 앱 설정에서 음성 안내가 켜짐 상태인지 확인하고, 스마트폰 음량이 최소로 되어 있지 않은지 확인하세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '앱 설정 > 음성 안내가 "켜짐" 상태인지 확인하세요.\n'
                  '스마트폰 음량이 최소로 되어 있지 않은지 확인하세요.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '데이터가 초기화됐어요.',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled(
                    "데이터가 초기화됐어요. 앱은 하이브를 통해 로컬에 데이터를 저장하므로, 기기를 변경하거나 앱을 삭제하면 기존 데이터는 복원되지 않습니다.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '앱은 Hive를 통해 로컬에 데이터를 저장하므로, '
                  '기기를 변경하거나 앱을 삭제하면 기존 데이터는 복원되지 않습니다.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '앱이 갑자기 종료돼요.',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.black,
                ),
              ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled(
                    "앱이 갑자기 종료돼요. 기기의 저장 공간이 부족하거나 메모리 사용량이 높을 때 종료될 수 있습니다. 불필요한 앱을 종료하거나 용량을 확보해 보세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '기기의 저장 공간이 부족하거나 메모리 사용량이 높을 때 종료될 수 있습니다. '
                  '불필요한 앱을 종료하거나 용량을 확보해 보세요.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '피드백을 보내고 싶어요.',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.black,
                ),  
              ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled(
                    "피드백을 보내고 싶어요. walkguide.feedback@gmail.com 이메일로 보내주세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '피드백을 남기시려면 walkguide.feedback@gmail.com 이메일로 보내주세요.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text(
              '실행 속도가 제대로 안 떠요.',
              style: TextStyle(
                fontSize: 20,
                color: Colors.black,
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _speakIfEnabled(
                    "실행 속도가 제대로 안 떠요. 앱은 일정한 걸음수, 최소 30걸음 이상을 기반으로 보행 속도를 분석합니다. 짧은 거리에서는 속도가 0.0 킬로미터로 나타날 수 있으니 충분히 이동해 보세요.");
              }
            },
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '앱은 일정한 걸음수(최소 30걸음 이상)를 기반으로 보행 속도를 분석합니다. '
                  '짧은 거리에서는 속도가 "0.0 km/h"로 나타날 수 있으니 충분히 이동해 보세요.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
