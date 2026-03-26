import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'zone_service.dart';

class SafetyService {
  List<AccidentZone> activeZones = [];
  final FlutterTts _tts = FlutterTts();

  // 🟢 NEW: Track the Zone IDs instead of time to prevent spamming
  int? _lastAlertedInsideZoneId;
  int? _lastAlertedApproachZoneId;

  DateTime? _lastMathCheck;

  Function(String title, String message, Color color)? onAlertPopup;

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
    // THROTTLE: Run math once per second maximum
    if (_lastMathCheck != null &&
        DateTime.now().difference(_lastMathCheck!).inMilliseconds < 1000) {
      return;
    }
    _lastMathCheck = DateTime.now();

    if (activeZones.isEmpty) return;

    int? triggeredInsideZoneId;
    int? triggeredApproachZoneId;

    double dynamicWarningDistance = (currentSpeedMetersPerSec * 20).clamp(
      50.0,
      600.0,
    );

    for (var zone in activeZones) {
      // BOUNDING BOX PRE-FILTER
      if ((markerPosition.latitude - zone.center.latitude).abs() > 0.006 ||
          (markerPosition.longitude - zone.center.longitude).abs() > 0.006) {
        continue;
      }

      // HAVERSINE DISTANCE MATH
      double distance = _calculateDistance(
        markerPosition.latitude,
        markerPosition.longitude,
        zone.center.latitude,
        zone.center.longitude,
      );

      // PRIORITY 1: INSIDE ZONE
      if (distance <= (zone.radius + 15)) {
        triggeredInsideZoneId = zone.id;
        break; // Stop checking, red alert is top priority
      }
      // PRIORITY 2: APPROACHING ZONE
      else if (distance <= (zone.radius + dynamicWarningDistance)) {
        double bearingToZone = _calculateBearing(markerPosition, zone.center);
        double headingDifference = (markerHeading - bearingToZone).abs();

        if (headingDifference > 180)
          headingDifference = 360 - headingDifference;

        if (headingDifference < 45) {
          triggeredApproachZoneId = zone.id;
        }
      }
    }

    // 🟢 DYNAMIC TRIGGER LOGIC (Zero Cooldown)
    if (triggeredInsideZoneId != null) {
      _triggerInsideAlert(triggeredInsideZoneId);
      _lastAlertedApproachZoneId = null; // Clear approach tracking if inside
    } else {
      // We are completely out of the red zone. Reset it instantly.
      _lastAlertedInsideZoneId = null;

      if (triggeredApproachZoneId != null) {
        _triggerApproachAlert(triggeredApproachZoneId);
      } else {
        // We are out of the orange zone. Reset it instantly.
        _lastAlertedApproachZoneId = null;
      }
    }
  }

  void _triggerApproachAlert(int zoneId) {
    // Only fire if it's a new zone we haven't just alerted for
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
    // Only fire if it's a new zone we haven't just alerted for
    if (_lastAlertedInsideZoneId != zoneId) {
      _tts.speak(
        "Caution. You are currently driving through a high-risk zone. Please reduce your speed and be safe.",
      );
      _lastAlertedInsideZoneId = zoneId;

      if (onAlertPopup != null) {
        onAlertPopup!(
          "Inside Hazard Zone",
          "You are currently driving through a high-risk area. Reduce speed and be safe.",
          Colors.red.shade900,
        );
      }
    }
  }
}
