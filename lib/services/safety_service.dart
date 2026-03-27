import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/accident_zone.dart';
import 'zone_service.dart';

class SafetyService {
  List<AccidentZone> activeZones = [];
  final FlutterTts _tts = FlutterTts();

  int? _lastAlertedInsideZoneId;
  int? _lastAlertedApproachZoneId;
  int? _lastAlertedMicroHotspotId;

  DateTime? _lastMathCheck;

  // Callbacks for the UI
  Function(String title, String message, Color color)? onAlertPopup;
  Function(MicroHotspot? hotspot, double? distance)? onHotspotUpdate;

  SafetyService() {
    _initTTS();
  }

  void _initTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> fetchDangerZones() async {
    try {
      activeZones = await ZoneService.fetchDangerZones();
    } catch (e) {
      debugPrint("❌ Failed to sync zones: $e");
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000;
    var dLat = _toRadians(lat2 - lat1);
    var dLon = _toRadians(lon2 - lon1);
    var a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double dLon = _toRadians(end.longitude - start.longitude);
    double y = sin(dLon) * cos(_toRadians(end.latitude));
    double x =
        cos(_toRadians(start.latitude)) * sin(_toRadians(end.latitude)) -
        sin(_toRadians(start.latitude)) *
            cos(_toRadians(end.latitude)) *
            cos(dLon);
    double bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }

  void checkProximity({
    required LatLng markerPosition,
    required double markerHeading,
    required double currentSpeedMetersPerSec,
  }) {
    if (_lastMathCheck != null &&
        DateTime.now().difference(_lastMathCheck!).inMilliseconds < 1000) {
      return;
    }
    _lastMathCheck = DateTime.now();

    if (activeZones.isEmpty) return;

    int? triggeredInsideZoneId;
    int? triggeredApproachZoneId;
    int? triggeredMicroHotspotId;

    MicroHotspot? closestHotspot;
    double? closestHotspotDistance;

    double dynamicWarningDistance = (currentSpeedMetersPerSec * 20).clamp(
      50.0,
      600.0,
    );
    double microWarningDistance = (currentSpeedMetersPerSec * 10).clamp(
      25.0,
      100.0,
    );

    for (var zone in activeZones) {
      if ((markerPosition.latitude - zone.centerLat).abs() > 0.006 ||
          (markerPosition.longitude - zone.centerLon).abs() > 0.006) {
        continue;
      }

      double distanceToZone = _calculateDistance(
        markerPosition.latitude,
        markerPosition.longitude,
        zone.centerLat,
        zone.centerLon,
      );

      // PRIORITY 1: INSIDE
      if (distanceToZone <= (zone.radiusMeters + 15)) {
        triggeredInsideZoneId = zone.zoneId;

        if (zone.microHotspots.isNotEmpty) {
          for (var hotspot in zone.microHotspots) {
            double distanceToHotspot = _calculateDistance(
              markerPosition.latitude,
              markerPosition.longitude,
              hotspot.lat,
              hotspot.lng,
            );

            // Are we close to the specific accident coordinate?
            if (distanceToHotspot <= microWarningDistance) {
              double bearingToHotspot = _calculateBearing(
                markerPosition,
                LatLng(hotspot.lat, hotspot.lng),
              );
              double hsHeadingDifference = (markerHeading - bearingToHotspot)
                  .abs();
              if (hsHeadingDifference > 180)
                hsHeadingDifference = 360 - hsHeadingDifference;

              if (hsHeadingDifference < 45) {
                if (distanceToHotspot > 10.0) {
                  if (closestHotspotDistance == null ||
                      distanceToHotspot < closestHotspotDistance!) {
                    closestHotspotDistance = distanceToHotspot;
                    closestHotspot = hotspot;
                    triggeredMicroHotspotId = hotspot.id;
                  }
                }
              }
            }
          }
        }
        break;
      }
      // PRIORITY 2: APPROACHING
      else if (distanceToZone <= (zone.radiusMeters + dynamicWarningDistance)) {
        double bearingToZone = _calculateBearing(
          markerPosition,
          LatLng(zone.centerLat, zone.centerLon),
        );
        double headingDifference = (markerHeading - bearingToZone).abs();

        if (headingDifference > 180)
          headingDifference = 360 - headingDifference;

        if (headingDifference < 45) {
          triggeredApproachZoneId = zone.zoneId;
        }
      }
    }

    if (onHotspotUpdate != null) {
      onHotspotUpdate!(closestHotspot, closestHotspotDistance);
    }

    if (triggeredInsideZoneId != null) {
      _triggerInsideAlert(triggeredInsideZoneId);
      _lastAlertedApproachZoneId = null;

      // 🟢 PASS THE DISTANCE TO THE ALERT METHOD
      if (triggeredMicroHotspotId != null && closestHotspotDistance != null) {
        _triggerMicroHotspotAlert(
          triggeredMicroHotspotId,
          closestHotspotDistance!,
        );
      } else {
        _lastAlertedMicroHotspotId = null;
      }
    } else {
      _lastAlertedInsideZoneId = null;
      _lastAlertedMicroHotspotId = null;

      if (triggeredApproachZoneId != null) {
        _triggerApproachAlert(triggeredApproachZoneId);
      } else {
        _lastAlertedApproachZoneId = null;
      }
    }
  }

  // 🟢 UPDATED: ADDED DISTANCE PARAMETER AND DYNAMIC AUDIO
  void _triggerMicroHotspotAlert(int hotspotId, double distance) {
    if (_lastAlertedMicroHotspotId != hotspotId) {
      String distanceText = distance.toStringAsFixed(0);
      _tts.speak(
        "Caution. Approaching a frequent accident area in $distanceText meters. Please reduce speed.",
      );
      _lastAlertedMicroHotspotId = hotspotId;

      if (onAlertPopup != null) {
        onAlertPopup!(
          "Accident Area Ahead",
          "You are approaching a frequent accident area in $distanceText meters. Please reduce speed.",
          Colors.deepPurple.shade900,
        );
      }
    }
  }

  void _triggerApproachAlert(int zoneId) {
    if (_lastAlertedApproachZoneId != zoneId) {
      _tts.speak("Heads up. You are approaching a high-risk driving zone.");
      _lastAlertedApproachZoneId = zoneId;

      if (onAlertPopup != null) {
        onAlertPopup!(
          "Approaching Hazard",
          "You are approaching a historically high-risk driving zone. Please stay alert.",
          Colors.orange.shade800,
        );
      }
    }
  }

  void _triggerInsideAlert(int zoneId) {
    if (_lastAlertedInsideZoneId != zoneId) {
      _tts.speak("Caution. You are entering a high-risk zone.");
      _lastAlertedInsideZoneId = zoneId;

      if (onAlertPopup != null) {
        onAlertPopup!(
          "Inside Hazard Zone",
          "You are currently driving through a high-risk area. Reduce speed.",
          Colors.red.shade900,
        );
      }
    }
  }
}
