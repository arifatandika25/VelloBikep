import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/bike_service.dart';

Set<Marker> buildFleetMarkers(List<Bike> bikes) {
  return {
    for (final bike in bikes)
      if (bike.hasLocation)
        Marker(
          markerId: MarkerId('bike-${bike.id}'),
          position: LatLng(bike.latitude!, bike.longitude!),
          infoWindow: InfoWindow(
            title: bike.name,
            snippet: 'No. ${bike.number} · GPS ${bike.gpsCode}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
  };
}

class FleetMap extends StatefulWidget {
  const FleetMap({super.key});

  @override
  State<FleetMap> createState() => _FleetMapState();
}

class _FleetMapState extends State<FleetMap> {
  final BikeService _bikeService = ApiBikeService();
  Set<Marker> _markers = {};
  String? _errorMessage;
  bool _isRefreshing = false;
  Timer? _refreshTimer;

  static const _initialPosition = CameraPosition(
    target: LatLng(-7.7956, 110.3695),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _refreshLocations();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshLocations(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocations() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final bikes = await _bikeService.getBikes();
      if (mounted) {
        setState(() {
          _markers = buildFleetMarkers(bikes);
          _errorMessage = null;
        });
      }
    } on BikeApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            mapType: MapType.normal,
            markers: _markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
          if (_errorMessage != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Material(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    'GPS tidak dapat diperbarui: $_errorMessage',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
