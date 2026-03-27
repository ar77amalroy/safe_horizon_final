import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'route_preview_screen.dart';
import 'profile_screen.dart';
import 'report_accident_screen.dart';
import 'services/map_matching_service.dart';
import 'services/location_tracking_service.dart';
import 'services/marker_animation_service.dart';
import 'services/osrm_service.dart';
import 'services/zone_service.dart';

// 🟢 NEW: Added the import for the updated model
import 'models/accident_zone.dart';

class DashboardScreen extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String? userPhone;

  const DashboardScreen({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  int _selectedTabIndex = 0;
  bool _isTrackingCamera = true;

  // State variable to control zone visibility
  bool _showDangerZones = true;

  LatLng? currentLocation;
  final MapController mapController = MapController();
  final LocationTrackingService locationService = LocationTrackingService();
  DateTime? _lastApiCallTime;

  List<AccidentZone> _dangerZones = [];

  @override
  void initState() {
    super.initState();

    _loadDangerZones();

    locationService.startTracking((location) {
      if (!mounted) return;

      final rawLocation = LatLng(location.latitude, location.longitude);
      final now = DateTime.now();

      _animateMarkerTo(rawLocation);

      if (_lastApiCallTime == null ||
          now.difference(_lastApiCallTime!).inSeconds >= 4) {
        _lastApiCallTime = now;
        _fetchSnappedLocationInBackground(rawLocation);
      }
    });
  }

  Future<void> _loadDangerZones() async {
    final zones = await ZoneService.fetchDangerZones();
    if (mounted) {
      setState(() {
        _dangerZones = zones;
      });
    }
  }

  void _animateMarkerTo(LatLng targetLocation) {
    if (currentLocation == null) {
      setState(() => currentLocation = targetLocation);
      return;
    }

    if (_isTrackingCamera) {
      mapController.move(targetLocation, mapController.camera.zoom);
    }

    MarkerAnimationService.animate(
      vsync: this,
      start: currentLocation!,
      end: targetLocation,
      onUpdate: (value) {
        if (!mounted) return;
        setState(() {
          currentLocation = value;
        });
      },
    );
  }

  Future<void> _fetchSnappedLocationInBackground(LatLng rawLoc) async {
    try {
      final snapped = await MapMatchingService.snapToRoad(rawLoc);
      if (snapped != null && mounted) {
        _animateMarkerTo(snapped);
      }
    } catch (e) {
      debugPrint("Map matching failed: $e");
    }
  }

  @override
  void dispose() {
    locationService.stopTracking();
    MarkerAnimationService.stop();
    super.dispose();
  }

  void _onBottomNavTapped(int index) {
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportAccidentScreen(userEmail: widget.userEmail),
        ),
      );
    } else if (index == 0) {
      setState(() => _selectedTabIndex = 0);
    } else if (index == 2) {
      setState(() => _selectedTabIndex = 1);
    }
  }

  int get _currentNavIndex {
    if (_selectedTabIndex == 0) return 0;
    return 2;
  }

  Widget _buildGlowingMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withOpacity(0.3),
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue,
          ),
        ),
      ),
    );
  }

  Widget _buildMapTab() {
    return currentLocation == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: currentLocation!,
                  initialZoom: 17.5,
                  onPointerDown: (_, __) {
                    setState(() => _isTrackingCamera = false);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'dev.safehorizon.app',
                  ),

                  // ==========================================
                  // 🟢 UPDATED: Only show if _showDangerZones is true
                  // ==========================================
                  if (_showDangerZones && _dangerZones.isNotEmpty)
                    CircleLayer(
                      // 🟢 FIXED: Added <CircleMarker> type casting
                      circles: _dangerZones.map<CircleMarker>((zone) {
                        final isHighRisk = zone.riskLevel == 'High';
                        return CircleMarker(
                          point: zone.center,
                          // 🟢 FIXED: Updated to use radiusMeters.toDouble()
                          radius: zone.radiusMeters.toDouble(),
                          useRadiusInMeter: true,
                          color: isHighRisk
                              ? Colors.red.withOpacity(0.3)
                              : Colors.orange.withOpacity(0.3),
                          borderColor: isHighRisk ? Colors.red : Colors.orange,
                          borderStrokeWidth: 2,
                        );
                      }).toList(),
                    ),

                  // ==========================================
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: currentLocation!,
                        width: 60,
                        height: 60,
                        child: _buildGlowingMarker(),
                      ),
                    ],
                  ),
                ],
              ),

              // THE AUTOCOMPLETE SEARCH BAR
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 20,
                right: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.length < 3) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      return await OsrmService.getAutocompleteSuggestions(
                        textEditingValue.text,
                      );
                    },
                    displayStringForOption: (option) =>
                        option['formatted'] as String,
                    onSelected: (Map<String, dynamic> selection) {
                      if (currentLocation != null) {
                        final destLatLng = LatLng(
                          selection['lat'],
                          selection['lon'],
                        );
                        final destName = selection['formatted'];

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoutePreviewScreen(
                              startLocation: currentLocation!,
                              destination: destLatLng,
                              destinationName: destName
                                  .toString()
                                  .split(',')[0]
                                  .toUpperCase(),
                            ),
                          ),
                        );
                      }
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: "Search Destination (e.g. Kottayam)...",
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.blue,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                            ),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: MediaQuery.of(context).size.width - 40,
                            constraints: const BoxConstraints(maxHeight: 250),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                    color: Colors.blue,
                                  ),
                                  title: Text(
                                    option['formatted'],
                                    style: const TextStyle(fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              Positioned(
                right: 15,
                bottom: 30,
                child: Column(
                  children: [
                    // Visibility Toggle Button
                    FloatingActionButton(
                      heroTag: "toggleZones",
                      mini: true,
                      backgroundColor: _showDangerZones
                          ? Colors.red.shade50
                          : Colors.white,
                      child: Icon(
                        _showDangerZones
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: _showDangerZones ? Colors.red : Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _showDangerZones = !_showDangerZones;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _showDangerZones
                                  ? "Danger Zones Visible"
                                  : "Danger Zones Hidden",
                            ),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),

                    FloatingActionButton(
                      heroTag: "zoomIn",
                      mini: true,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.add, color: Colors.black87),
                      onPressed: () {
                        mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom + 1,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      heroTag: "zoomOut",
                      mini: true,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.remove, color: Colors.black87),
                      onPressed: () {
                        mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom - 1,
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    FloatingActionButton(
                      heroTag: "myLocation",
                      backgroundColor: _isTrackingCamera
                          ? Colors.blue
                          : Colors.white,
                      child: Icon(
                        Icons.my_location,
                        color: _isTrackingCamera ? Colors.white : Colors.blue,
                      ),
                      onPressed: () async {
                        setState(() => _isTrackingCamera = true);

                        if (currentLocation != null) {
                          mapController.move(currentLocation!, 17.5);
                        }

                        try {
                          Position pos = await Geolocator.getCurrentPosition(
                            desiredAccuracy: LocationAccuracy.high,
                          );
                          _animateMarkerTo(LatLng(pos.latitude, pos.longitude));
                        } catch (e) {
                          debugPrint("Manual GPS fetch failed: $e");
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildMapTab(),
          ProfileScreen(
            name: widget.userName,
            email: widget.userEmail,
            phone: widget.userPhone,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: _onBottomNavTapped,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline, size: 28),
            label: "Report",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
