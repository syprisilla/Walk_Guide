import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:walk_guide/map/map_screen.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('MapScreen이 FlutterMap을 포함하고 있어야 함', (WidgetTester tester) async {
    final mapController = MapController();
    final currentLocation = LatLng(37.5665, 126.9780);

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          currentLocation: currentLocation,
          mapController: mapController,
        ),
      ),
    );

    // FlutterMap 위젯이 존재하는지 확인
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
