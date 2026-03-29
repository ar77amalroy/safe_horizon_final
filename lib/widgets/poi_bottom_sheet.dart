import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// Make sure these imports match your actual folder structure!
import '../services/poi_service.dart';
import '../route_preview_screen.dart';

class PoiBottomSheet {
  static Future<void> show(
    BuildContext context,
    String category,
    LatLng currentLocation,
  ) async {
    // 1. Close the options menu first
    Navigator.pop(context);

    // 2. Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    // 3. Fetch places from TomTom
    final places = await PoiService.getNearbyPlaces(category, currentLocation);

    // 4. Close the loading dialog
    if (context.mounted) Navigator.pop(context);

    // 5. Show the results in a new Bottom Sheet
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Nearby $category",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                Expanded(
                  child: places.isEmpty
                      ? const Center(child: Text("No places found nearby."))
                      : ListView.separated(
                          itemCount: places.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            final place = places[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade50,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.blue,
                                ),
                              ),
                              title: Text(
                                place['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text("Tap to view route"),
                              trailing: const Icon(
                                Icons.directions,
                                color: Colors.green,
                              ),
                              onTap: () {
                                Navigator.pop(context); // Close the list sheet

                                final target = LatLng(
                                  place['lat'],
                                  place['lon'],
                                );
                                final destName = place['name'];

                                // Navigate to Route Screen
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RoutePreviewScreen(
                                      startLocation: currentLocation,
                                      destination: target,
                                      destinationName: destName,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    }
  }
}
