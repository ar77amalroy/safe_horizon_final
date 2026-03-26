import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'api_service.dart'; // Uses your existing baseUrl

// 1. The Blueprint for an Accident Zone
class AccidentZone {
  final int id;
  final LatLng center;
  final double radius;
  final String riskLevel;
  final int score;

  AccidentZone({
    required this.id,
    required this.center,
    required this.radius,
    required this.riskLevel,
    required this.score,
  });

  // Converts the Python JSON into a Flutter Object
  factory AccidentZone.fromJson(Map<String, dynamic> json) {
    return AccidentZone(
      id: json['zone_id'],
      center: LatLng(json['center_lat'], json['center_lon']),
      radius: (json['radius_meters'] as num).toDouble(),
      riskLevel: json['risk_level'],
      score: json['score'],
    );
  }
}

// 2. The Service that fetches the data from your FastAPI backend
class ZoneService {
  static Future<List<AccidentZone>> fetchDangerZones() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/accident-zones'),
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => AccidentZone.fromJson(json)).toList();
      }
    } catch (e) {
      print("❌ Failed to fetch accident zones: $e");
    }
    return [];
  }
}
