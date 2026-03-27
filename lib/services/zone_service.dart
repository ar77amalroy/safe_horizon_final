import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/accident_zone.dart';
import 'api_service.dart';

class ZoneService {
  static Future<List<AccidentZone>> fetchDangerZones() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/accident-zones'),
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => AccidentZone.fromJson(json)).toList();
      } else {
        debugPrint("Failed to load zones: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Zone fetch error: $e");
    }
    return [];
  }
}
