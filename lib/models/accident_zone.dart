import 'package:latlong2/latlong.dart';

class MicroHotspot {
  final int id;
  final double lat;
  final double lng;
  final String severity;
  final int radiusMeters;

  MicroHotspot({
    required this.id,
    required this.lat,
    required this.lng,
    required this.severity,
    required this.radiusMeters,
  });

  factory MicroHotspot.fromJson(Map<String, dynamic> json) {
    return MicroHotspot(
      id: int.tryParse(json['hotspot_id']?.toString() ?? '0') ?? 0,
      lat: double.tryParse(json['lat']?.toString() ?? '0.0') ?? 0.0,
      lng: double.tryParse(json['lng']?.toString() ?? '0.0') ?? 0.0,
      severity: json['severity']?.toString() ?? "Minor",
      radiusMeters:
          int.tryParse(
            json['radius_meters']?.toString().split('.').first ?? '50',
          ) ??
          50,
    );
  }
}

class AccidentZone {
  final int zoneId;
  final double centerLat;
  final double centerLon;
  final int radiusMeters;
  final String riskLevel;
  final List<MicroHotspot> microHotspots;
  final LatLng center;

  AccidentZone({
    required this.zoneId,
    required this.centerLat,
    required this.centerLon,
    required this.radiusMeters,
    required this.riskLevel,
    required this.microHotspots,
  }) : center = LatLng(centerLat, centerLon);

  factory AccidentZone.fromJson(Map<String, dynamic> json) {
    var list = json['micro_hotspots'] as List? ?? [];
    List<MicroHotspot> hotspotList = list
        .map((i) => MicroHotspot.fromJson(i as Map<String, dynamic>))
        .toList();

    return AccidentZone(
      zoneId: int.tryParse(json['zone_id']?.toString() ?? '0') ?? 0,
      centerLat:
          double.tryParse(json['center_lat']?.toString() ?? '0.0') ?? 0.0,
      centerLon:
          double.tryParse(json['center_lon']?.toString() ?? '0.0') ?? 0.0,
      radiusMeters:
          int.tryParse(
            json['radius_meters']?.toString().split('.').first ?? '150',
          ) ??
          150,
      riskLevel: json['risk_level']?.toString() ?? "Medium",
      microHotspots: hotspotList,
    );
  }
}
