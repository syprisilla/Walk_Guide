// File: lib/map/map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatelessWidget {
  final LatLng? currentLocation;
  final MapController mapController;

  const MapScreen({
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
        minZoom: 3.0,
        maxZoom: 18.0,
        maxBounds: LatLngBounds(
          LatLng(-85.0, -180.0),
          LatLng(85.0, 180.0),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.oss.walk_guide',
          tileProvider: NetworkTileProvider(),
          tileSize: 256,
          retinaMode: true,
          backgroundColor: Colors.white,
        ),
        if (currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: currentLocation!,
                width: 50,
                height: 50,
                child: Image.asset(
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
