import 'dart:async';
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
import 'services/location_search_service.dart';
import 'services/zone_service.dart';

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

  // 🟢 Toggles for the map layers
  bool _showDangerZones = true;
  bool _showTraffic = false; // Defaulted to false to save your API quota
  final String tomTomApiKey = "e4fD2NJaHWYFBFKE2oCAoFeYnmAInn6o";

  LatLng? currentLocation;
  final MapController mapController = MapController();
  final LocationTrackingService locationService = LocationTrackingService();
  DateTime? _lastApiCallTime;

  List<AccidentZone> _dangerZones = [];

  // --- SEARCH STATE VARIABLES ---
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

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

  // --- SEARCH LOGIC (DEBOUNCED) ---
  void _onSearchChanged(String query) {
    setState(() {});

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);

      final results = await LocationSearchService.searchPlaces(
        query,
        currentLocation,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _onSearchResultSelected(Map<String, dynamic> place) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
      _isTrackingCamera = false;
    });

    final target = LatLng(place['lat'], place['lon']);
    final destName = place['name'].toString().split(',')[0].toUpperCase();

    mapController.move(target, 15.0);

    if (currentLocation != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoutePreviewScreen(
            startLocation: currentLocation!,
            destination: target,
            destinationName: destName,
          ),
        ),
      );
    }
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
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    }
  }

  int get _currentNavIndex {
    return _selectedTabIndex == 0 ? 0 : 1;
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

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.black87, size: 24),
      ),
    );
  }

  // --- UNIFIED OPTIONS MENU (BOTTOM SHEET) ---
  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close, color: Colors.grey.shade700),
                    ),
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.blue.shade100,
                      child: Icon(
                        Icons.person,
                        color: Colors.blue.shade800,
                        size: 30,
                      ),
                    ),
                    title: Text(
                      widget.userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: const Text("Profile Settings"),
                    trailing: const Icon(Icons.settings_outlined),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            name: widget.userName,
                            email: widget.userEmail,
                            phone: widget.userPhone,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // RISK ZONES TOGGLE
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade500,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.visibility,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Risk Zones",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                "Toggle risk area views on/off",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showDangerZones,
                          activeColor: Colors.red.shade500,
                          onChanged: (val) {
                            setModalState(() => _showDangerZones = val);
                            setState(() => _showDangerZones = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // LIVE TRAFFIC TOGGLE
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade500,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.traffic,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Live Traffic",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                "Show real-time road congestion",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showTraffic,
                          activeColor: Colors.orange.shade500,
                          onChanged: (val) {
                            setModalState(() => _showTraffic = val);
                            setState(() => _showTraffic = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const Icon(
                      Icons.settings_suggest_outlined,
                      size: 28,
                    ),
                    title: const Text(
                      "App Settings",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
        );
      },
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
                  initialZoom: 14.0,
                  onPointerDown: (_, __) {
                    setState(() => _isTrackingCamera = false);
                  },
                ),
                children: [
                  // 1. Base Map Layer
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'dev.safehorizon.app',
                    keepBuffer: 3,
                  ),

                  // 🟢 2. TomTom Live Traffic Overlay (Fixed for v8.2.2)
                  if (_showTraffic)
                    TileLayer(
                      urlTemplate:
                          'https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key=$tomTomApiKey',
                      userAgentPackageName: 'dev.safehorizon.app',
                    ),

                  // 3. Danger Zones Layer
                  if (_showDangerZones && _dangerZones.isNotEmpty)
                    CircleLayer(
                      circles: _dangerZones.expand<CircleMarker>((zone) {
                        final isHighRisk = zone.riskLevel == 'High';

                        return [
                          CircleMarker(
                            point: zone.center,
                            radius: zone.radiusMeters.toDouble() + 1500.0,
                            useRadiusInMeter: true,
                            color: Colors.yellow.withOpacity(0.1),
                            borderColor: Colors.yellow.withOpacity(0.5),
                            borderStrokeWidth: 1,
                          ),
                          CircleMarker(
                            point: zone.center,
                            radius: zone.radiusMeters.toDouble(),
                            useRadiusInMeter: true,
                            color: isHighRisk
                                ? Colors.red.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                            borderColor: isHighRisk
                                ? Colors.red
                                : Colors.orange,
                            borderStrokeWidth: 2,
                          ),
                        ];
                      }).toList(),
                    ),

                  // 4. User Marker Layer
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

              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    Material(
                      elevation: 6,
                      shadowColor: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      color: Colors.white,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search Destination...",
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 12.0),
                            child: Icon(
                              Icons.search,
                              color: Color(0xFF1976D2),
                              size: 26,
                            ),
                          ),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(14.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.cancel,
                                    color: Colors.grey.shade400,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchFocusNode.unfocus();
                                    setState(() {
                                      _searchResults = [];
                                      _isSearching = false;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),

                    if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _searchResults.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, index) {
                              final place = _searchResults[index];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Color(0xFF1976D2),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  place['name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onTap: () => _onSearchResultSelected(place),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Column(
                        children: [
                          _buildZoomButton(Icons.add, () {
                            mapController.move(
                              mapController.camera.center,
                              mapController.camera.zoom + 1,
                            );
                          }),
                          Container(
                            height: 1,
                            width: 32,
                            color: Colors.grey.shade200,
                          ),
                          _buildZoomButton(Icons.remove, () {
                            mapController.move(
                              mapController.camera.center,
                              mapController.camera.zoom - 1,
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Material(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          setState(() => _isTrackingCamera = true);
                          if (currentLocation != null) {
                            mapController.move(currentLocation!, 17.5);
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.my_location,
                                color: _isTrackingCamera
                                    ? const Color(0xFF1976D2)
                                    : Colors.black87,
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Locate Me",
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    elevation: 6,
                    shadowColor: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.white,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: _showOptionsMenu,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              size: 20,
                              color: Colors.grey.shade800,
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.grey.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Options Menu",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: _onBottomNavTapped,
          selectedItemColor: const Color(0xFF1976D2),
          unselectedItemColor: Colors.grey.shade600,
          showUnselectedLabels: true,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 13,
          unselectedFontSize: 13,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.location_on, size: 26),
              ),
              label: "Map",
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.feed_outlined, size: 26),
              ),
              label: "Report",
            ),
          ],
        ),
      ),
    );
  }
}
