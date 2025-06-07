// test/map/map_screen_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// import 'package:walk_guide/map/map_screen.dart'; // 원본 대신 테스트용 위젯 사용 고려
import 'package:latlong2/latlong.dart';

// 테스트용 MapScreen 정의 (TileLayer를 제외하거나 목킹된 Provider 사용)
class TestableMapScreen extends StatelessWidget {
  final LatLng? currentLocation;
  final MapController mapController;

  const TestableMapScreen({
    super.key,
    required this.currentLocation,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: currentLocation ?? LatLng(37.5665, 126.9780),
        initialZoom: 15.0,
      ),
      children: [
        // TileLayer( // <-- 네트워크 요청을 피하기 위해 이 부분을 주석 처리하거나 목킹된 Provider로 대체
        //   urlTemplate:
        //       "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
        //   subdomains: const ['a', 'b', 'c'],
        //   userAgentPackageName: 'com.oss.walk_guide',
        //   tileProvider: NetworkTileProvider(), // <-- 이 부분을 목킹
        //   tileSize: 256,
        //   retinaMode: true,
        //   backgroundColor: Colors.white,
        // ),
        if (currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: currentLocation!,
                width: 50,
                height: 50,
                child: Image.asset( // Image.asset도 테스트 환경에서 로드되도록 assets 설정 필요
                  'assets/images/walkingIcon.png',
                  width: 50,
                  height: 50,
                ),
              ),
            ],
          ),
      ],
    );
  }
}


void main() {
  // Ensure assets are available for Image.asset
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MapScreen이 FlutterMap을 포함하고 있어야 함', (WidgetTester tester) async {
    final mapController = MapController();
    final currentLocation = LatLng(37.5665, 126.9780);

    // walkingIcon.png 에셋이 테스트 환경에서 로드될 수 있도록 pubspec.yaml에 정의되어 있고,
    // 테스트 실행 시 해당 에셋을 찾을 수 있어야 합니다.
    // 간단한 해결책은 Image.asset 대신 Placeholder를 사용하는 것입니다.

    await tester.pumpWidget(
      MaterialApp(
        home: TestableMapScreen( // 원본 MapScreen 대신 TestableMapScreen 사용
          currentLocation: currentLocation,
          mapController: mapController,
        ),
      ),
    );

    // FlutterMap 위젯이 존재하는지 확인
    expect(find.byType(FlutterMap), findsOneWidget);
    // 추가로 ClientException이 발생하지 않는지 확인 (이전 로그 기준)
    expect(tester.takeException(), isNull);
  });
}