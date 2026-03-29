import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationSearchService {
  // Your Geoapify key
  static const String _geoapifyKey = "fd24e74b5e854fa4981cdd39f8452044";

  static Future<List<Map<String, dynamic>>> searchPlaces(
    String query,
    LatLng? currentLocation,
  ) async {
    // Don't waste API calls on 1 or 2 letter searches
    if (query.trim().length < 3) return [];

    String url =
        "https://api.geoapify.com/v1/geocode/autocomplete"
        "?text=$query&limit=5&apiKey=$_geoapifyKey";

    // Bias results to the user's current location
    if (currentLocation != null) {
      url +=
          "&bias=proximity:${currentLocation.longitude},${currentLocation.latitude}";
    }

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List;

        return features.map((feature) {
          final props = feature['properties'];
          return {
            "name": props['formatted'] ?? props['name'] ?? "Unknown Location",
            "lat": props['lat'],
            "lon": props['lon'],
          };
        }).toList();
      }
    } catch (e) {
      print("Search error: $e");
    }

    return [];
  }
}
