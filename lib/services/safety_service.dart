import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'zone_service.dart';

class SafetyService {
  List<AccidentZone> activeZones = [];
  final FlutterTts _tts = FlutterTts();

  DateTime? _lastApproachAlert;
  DateTime? _lastInsideAlert;

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
      print("❌ Failed to sync zones: $e");
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

  // 🟢 THE FIX: Priority Checking Logic
  void checkProximity(Position currentPos) {
    if (activeZones.isEmpty) return;

    bool isInside = false;
    bool isApproaching = false;

    // First, scan ALL zones to figure out the highest threat level
    for (var zone in activeZones) {
      double distance = _calculateDistance(
        currentPos.latitude,
        currentPos.longitude,
        zone.center.latitude,
        zone.center.longitude,
      );

      // We add a 15m buffer so it triggers even if you just clip the edge of the circle!
      if (distance <= (zone.radius + 15)) {
        isInside = true;
      } else if (distance <= (zone.radius + 500)) {
        isApproaching = true;
      }
    }

    // Now, trigger the UI based on the HIGHEST priority
    // Priority 1: If we are inside ANY zone, trigger RED.
    if (isInside) {
      _triggerInsideAlert();
    }
    // Priority 2: Only trigger ORANGE if we are approaching, but NOT inside a different zone.
    else if (isApproaching) {
      _triggerApproachAlert();
    }
  }

  void _triggerApproachAlert() {
    if (_lastApproachAlert == null ||
        DateTime.now().difference(_lastApproachAlert!).inMinutes > 5) {
      _tts.speak("Heads up. You are approaching a high-risk driving zone.");
      _lastApproachAlert = DateTime.now();

      if (onAlertPopup != null) {
        onAlertPopup!(
          "Approaching Hazard",
          "You are approaching a historically high-risk driving zone. Please stay alert.",
          Colors.orange.shade800,
        );
      }
    }
  }

  void _triggerInsideAlert() {
    if (_lastInsideAlert == null ||
        DateTime.now().difference(_lastInsideAlert!).inMinutes > 5) {
      _tts.speak(
        "Caution. You are currently driving through a high-risk zone. Please reduce your speed and be safe.",
      );
      _lastInsideAlert = DateTime.now();

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
