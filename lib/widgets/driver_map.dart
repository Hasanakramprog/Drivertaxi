// lib/widgets/driver_map.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:taxi_driver_app/services/hotspot_service.dart';
import 'package:flutter/services.dart'; // Add this import at the top
// Add these imports at the top
import 'dart:ui' as ui;
import 'dart:typed_data';

class DriverMap extends StatefulWidget {
  const DriverMap({Key? key}) : super(key: key);

  @override
  State<DriverMap> createState() => _DriverMapState();
}

class _DriverMapState extends State<DriverMap> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Circle> _circles = {}; // Add this for red zones
  // Add these variables for custom taxi icons
  BitmapDescriptor? _taxiOnlineIcon;
  BitmapDescriptor? _taxiOfflineIcon;
  bool _iconsLoaded = false;
  // Map camera position - will be updated based on current location
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(33.8938, 35.5018), // Beirut, Lebanon coordinates
    zoom: 14.0,
  );

  bool _mapInitialized = false;
  bool _isMapLoading = true;
  bool _isLocationLoading = true;
  String _loadingStatus = 'Loading map...';

  // Add these variables for hotspots
  List<Map<String, dynamic>> _hotspots = [];
  bool _showHotspots = false;
  bool _isLoadingHotspots = false;

  @override
  void initState() {
    super.initState();
    // Load custom icons first
    _loadCustomIcons();

    // Start location initialization after a short delay to let map start loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationAfterDelay();
      _loadHotspots(); // Add this
    });
  }

  // Add this method after _updateHotspotCircles()
  Future<void> _zoomToShowAllHotspots() async {
    if (_hotspots.isEmpty) {
      print('🔥 No hotspots to zoom to');
      return;
    }

    try {
      final controller = await _controller.future;

      // Calculate bounds for all hotspots
      List<LatLng> hotspotPoints = [];

      for (var hotspot in _hotspots) {
        final center = hotspot['center'];
        if (center != null) {
          hotspotPoints.add(
            LatLng(
              (center['latitude'] ?? 0.0).toDouble(),
              (center['longitude'] ?? 0.0).toDouble(),
            ),
          );
        }
      }

      if (hotspotPoints.isEmpty) return;

      // If only one hotspot, zoom to it
      if (hotspotPoints.length == 1) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: hotspotPoints.first,
              zoom: 12.0, // Zoom level to see 2km radius
            ),
          ),
        );
        return;
      }

      // Calculate bounds for multiple hotspots
      double minLat = hotspotPoints.first.latitude;
      double maxLat = hotspotPoints.first.latitude;
      double minLng = hotspotPoints.first.longitude;
      double maxLng = hotspotPoints.first.longitude;

      for (var point in hotspotPoints) {
        minLat = minLat < point.latitude ? minLat : point.latitude;
        maxLat = maxLat > point.latitude ? maxLat : point.latitude;
        minLng = minLng < point.longitude ? minLng : point.longitude;
        maxLng = maxLng > point.longitude ? maxLng : point.longitude;
      }

      // Add padding to show the full circles (2km radius ≈ 0.018 degrees)
      const padding = 0.025;

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - padding, minLng - padding),
            northeast: LatLng(maxLat + padding, maxLng + padding),
          ),
          100.0, // padding in pixels
        ),
      );

      print('🔥 Zoomed to show ${hotspotPoints.length} hotspots');
    } catch (e) {
      print('🔥 Error zooming to hotspots: $e');
    }
  }

  // Create professional taxi car icon with direction indicator
  Future<BitmapDescriptor> _createTaxiIcon(bool isOnline) async {
    return await BitmapDescriptor.fromBytes(await _drawTaxiCar(isOnline));
  }

  // Draw a professional taxi car icon
  Future<Uint8List> _drawTaxiCar(bool isOnline) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 120.0;
    const double carWidth = 80.0;
    const double carHeight = 100.0;
    final centerX = size / 2;
    final centerY = size / 2;

    // Status color
    final statusColor = isOnline ? Colors.green : Colors.red;

    // Draw shadow
    final shadowPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, centerY + carHeight / 2 + 5),
        width: carWidth * 0.8,
        height: 15,
      ),
      shadowPaint,
    );

    // Draw car body (main rectangle)
    final carBodyPaint =
        Paint()
          ..color = statusColor
          ..style = PaintingStyle.fill;

    final carRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: carWidth * 0.6,
        height: carHeight * 0.7,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(carRect, carBodyPaint);

    // Draw car roof/cabin (smaller rectangle on top)
    final roofPaint = Paint()..color = statusColor.withOpacity(0.85);
    final roofRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY - carHeight * 0.15),
        width: carWidth * 0.45,
        height: carHeight * 0.35,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(roofRect, roofPaint);

    // Draw windows (white rectangles)
    final windowPaint = Paint()..color = Colors.white.withOpacity(0.9);

    // Front window
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, centerY - carHeight * 0.25),
          width: carWidth * 0.35,
          height: carHeight * 0.15,
        ),
        const Radius.circular(3),
      ),
      windowPaint,
    );

    // Rear window
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, centerY - carHeight * 0.05),
          width: carWidth * 0.35,
          height: carHeight * 0.15,
        ),
        const Radius.circular(3),
      ),
      windowPaint,
    );

    // Draw headlights (small yellow circles at front)
    final headlightPaint = Paint()..color = Colors.yellow.shade300;
    canvas.drawCircle(
      Offset(centerX - carWidth * 0.15, centerY + carHeight * 0.28),
      4,
      headlightPaint,
    );
    canvas.drawCircle(
      Offset(centerX + carWidth * 0.15, centerY + carHeight * 0.28),
      4,
      headlightPaint,
    );

    // Draw "TAXI" sign on roof
    final taxiSignPaint = Paint()..color = Colors.yellow.shade600;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, centerY - carHeight * 0.38),
          width: carWidth * 0.25,
          height: carHeight * 0.08,
        ),
        const Radius.circular(2),
      ),
      taxiSignPaint,
    );

    // Draw direction arrow (pointing up/forward)
    final arrowPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

    final arrowPath = Path();
    final arrowTop = centerY - carHeight * 0.45;
    final arrowSize = 12.0;

    arrowPath.moveTo(centerX, arrowTop); // Arrow tip
    arrowPath.lineTo(
      centerX - arrowSize / 2,
      arrowTop + arrowSize,
    ); // Left point
    arrowPath.lineTo(
      centerX - arrowSize / 4,
      arrowTop + arrowSize,
    ); // Left inner
    arrowPath.lineTo(
      centerX - arrowSize / 4,
      arrowTop + arrowSize * 1.5,
    ); // Left bottom
    arrowPath.lineTo(
      centerX + arrowSize / 4,
      arrowTop + arrowSize * 1.5,
    ); // Right bottom
    arrowPath.lineTo(
      centerX + arrowSize / 4,
      arrowTop + arrowSize,
    ); // Right inner
    arrowPath.lineTo(
      centerX + arrowSize / 2,
      arrowTop + arrowSize,
    ); // Right point
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Draw white border around entire icon
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    canvas.drawCircle(
      Offset(centerX, centerY),
      size / 2 - 2,
      Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(Offset(centerX, centerY), size / 2 - 4, borderPaint);

    final ui.Picture picture = pictureRecorder.endRecording();
    final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  // Load custom professional taxi car icons
  Future<void> _loadCustomIcons() async {
    try {
      print('🚕 Creating custom taxi car icons...');

      _taxiOnlineIcon = await _createTaxiIcon(true);
      _taxiOfflineIcon = await _createTaxiIcon(false);

      setState(() {
        _iconsLoaded = true;
      });

      print('🚕 Custom taxi car icons created successfully');
    } catch (e) {
      print('🚕 Error creating custom icons: $e');
      // Will fallback to default icons
    }
  }

  // Add this method to load hotspots
  Future<void> _loadHotspots() async {
    print('🔥 Starting to load hotspots...');

    if (mounted) {
      setState(() {
        _isLoadingHotspots = true;
      });
    }

    try {
      // Try function first, fallback to direct Firestore
      List<Map<String, dynamic>> hotspots =
          await HotspotService.getHotspotsFromFunction();

      if (hotspots.isEmpty) {
        print('🔥 Function returned empty, trying Firestore...');
        hotspots = await HotspotService.getHotspotsFromFirestore();
      }

      print('🔥 Loaded ${hotspots.length} hotspots');
      print('🔥 Hotspots data: $hotspots');

      if (mounted) {
        setState(() {
          _hotspots = hotspots;
          _isLoadingHotspots = false;
        });
        _updateHotspotCircles();
      }
    } catch (e) {
      print('🔥 Error loading hotspots: $e');
      if (mounted) {
        setState(() {
          _isLoadingHotspots = false;
        });
      }
    }
  }

  // Add this method to update hotspot circles
  void _updateHotspotCircles() {
    _circles.clear();

    if (!_showHotspots) return;

    for (var hotspot in _hotspots) {
      final center = hotspot['center'];
      if (center == null) continue;

      final intensity = hotspot['intensity'] as String? ?? 'low';

      // Different colors based on intensity
      Color zoneColor;
      double strokeWidth;

      switch (intensity) {
        case 'high':
          zoneColor = Colors.red.withOpacity(0.3);
          strokeWidth = 3.0;
          break;
        case 'medium':
          zoneColor = Colors.orange.withOpacity(0.25);
          strokeWidth = 2.0;
          break;
        case 'low':
          zoneColor = Colors.yellow.withOpacity(0.2);
          strokeWidth = 1.5;
          break;
        default:
          zoneColor = Colors.red.withOpacity(0.3);
          strokeWidth = 2.0;
      }

      _circles.add(
        Circle(
          circleId: CircleId(hotspot['id'] ?? 'hotspot_${_circles.length}'),
          center: LatLng(
            (center['latitude'] ?? 0.0).toDouble(),
            (center['longitude'] ?? 0.0).toDouble(),
          ),
          radius: (hotspot['radius'] ?? 2000).toDouble(),
          fillColor: zoneColor,
          strokeColor: zoneColor.withOpacity(0.8),
          strokeWidth: strokeWidth.toInt(),
        ),
      );
    }
  }

  // Initialize location after a short delay
  Future<void> _initializeLocationAfterDelay() async {
    // Let the map start loading first
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _loadingStatus = 'Getting your location...';
      });
    }

    await _initializeMapWithCurrentLocation();
  }

  // Initialize map with current location and set up LocationProvider
  Future<void> _initializeMapWithCurrentLocation() async {
    try {
      final locationProvider = Provider.of<LocationProvider>(
        context,
        listen: false,
      );

      // Ensure location provider is initialized
      if (!locationProvider.hasPermission) {
        if (mounted) {
          setState(() {
            _loadingStatus = 'Requesting location permission...';
          });
        }
        await locationProvider.initialize();
      }

      // Get current location and update camera position
      if (locationProvider.currentPosition != null) {
        _updateInitialCameraPosition(locationProvider);
      } else {
        if (mounted) {
          setState(() {
            _loadingStatus = 'Locating your position...';
          });
        }
        // Request current location if not available
        await locationProvider.getCurrentLocationAndNavigate();
        if (locationProvider.currentPosition != null) {
          _updateInitialCameraPosition(locationProvider);
        }
      }

      // Mark location as loaded
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
          _loadingStatus = 'Location found!';
        });

        // Hide loading after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _loadingStatus = '';
            });
          }
        });
      }
    } catch (e) {
      print('Error initializing location: $e');
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
          _loadingStatus = 'Location unavailable';
        });

        // Hide error message after delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _loadingStatus = '';
            });
          }
        });
      }
    }
  }

  // Update the initial camera position based on current location
  void _updateInitialCameraPosition(LocationProvider locationProvider) {
    final position = locationProvider.currentPosition;
    if (position?.latitude != null &&
        position?.longitude != null &&
        !_mapInitialized) {
      // Use WidgetsBinding to defer setState until after the current build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_mapInitialized) {
          setState(() {
            _initialCameraPosition = CameraPosition(
              target: LatLng(position!.latitude!, position.longitude!),
              zoom: 16,
              bearing: position.heading ?? 0.0,
            );
            _mapInitialized = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocationProvider, TripProvider>(
      builder: (context, locationProvider, tripProvider, _) {
        // Check if we need to update camera position, but don't call setState here
        if (locationProvider.currentPosition != null && !_mapInitialized) {
          // Schedule the update for after this build completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateInitialCameraPosition(locationProvider);
          });
        }

        // Update markers and polylines based on current data
        _updateMapData(locationProvider, tripProvider);

        return Stack(
          children: [
            // Google Map
            GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              mapType:
                  MapType
                      .terrain, // Terrain view - faster loading than hybrid, shows roads with topography
              myLocationEnabled:
                  false, // Disable default blue dot since we have custom taxi marker
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              compassEnabled: true,
              trafficEnabled:
                  true, // Enable real-time traffic layer - critical for taxi drivers
              markers: _markers,
              polylines: _polylines,
              circles: _circles, // Add this line
              onMapCreated: (GoogleMapController controller) async {
                _controller.complete(controller);

                // Mark map as loaded
                if (mounted) {
                  setState(() {
                    _isMapLoading = false;
                  });
                }

                // Set the controller in LocationProvider for automatic navigation
                locationProvider.setMapController(controller);

                // Center map on current location once controller is ready
                if (locationProvider.currentPosition != null) {
                  await _centerMapOnCurrentLocation(locationProvider);
                }
              },
            ),

            // Loading Overlay
            if (_isMapLoading ||
                _isLocationLoading ||
                _loadingStatus.isNotEmpty)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Map loading indicator
                      if (_isMapLoading)
                        Column(
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                              strokeWidth: 3,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Loading map...',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                      // Location loading indicator
                      if (!_isMapLoading &&
                          (_isLocationLoading || _loadingStatus.isNotEmpty))
                        Column(
                          children: [
                            if (_isLocationLoading)
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.green,
                                ),
                                strokeWidth: 3,
                              )
                            else if (_loadingStatus.contains('found'))
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 48,
                              )
                            else if (_loadingStatus.contains('unavailable'))
                              const Icon(
                                Icons.location_off,
                                color: Colors.red,
                                size: 48,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _loadingStatus,
                              style: TextStyle(
                                fontSize: 16,
                                color:
                                    _loadingStatus.contains('found')
                                        ? Colors.green[700]
                                        : _loadingStatus.contains('unavailable')
                                        ? Colors.red[700]
                                        : Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                      // Progress indicator for sequential loading
                      if (_isMapLoading || _isLocationLoading)
                        Container(
                          margin: const EdgeInsets.only(top: 24),
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  // Map loading step
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          !_isMapLoading
                                              ? Colors.green
                                              : Colors.blue,
                                      border: Border.all(
                                        color:
                                            !_isMapLoading
                                                ? Colors.green
                                                : Colors.blue,
                                        width: 2,
                                      ),
                                    ),
                                    child:
                                        !_isMapLoading
                                            ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                            : const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      color:
                                          !_isMapLoading
                                              ? Colors.green
                                              : Colors.grey[300],
                                    ),
                                  ),
                                  // Location loading step
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          !_isLocationLoading
                                              ? Colors.green
                                              : _isMapLoading
                                              ? Colors.grey[300]
                                              : Colors.blue,
                                      border: Border.all(
                                        color:
                                            !_isLocationLoading
                                                ? Colors.green
                                                : _isMapLoading
                                                ? Colors.grey[300]!
                                                : Colors.blue,
                                        width: 2,
                                      ),
                                    ),
                                    child:
                                        !_isLocationLoading
                                            ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                            : !_isMapLoading
                                            ? const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            )
                                            : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Map',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          !_isMapLoading
                                              ? Colors.green
                                              : Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          !_isLocationLoading
                                              ? Colors.green
                                              : _isMapLoading
                                              ? Colors.grey[400]
                                              : Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // // Custom "My Location" button (only show when loading is complete)
            // if (!_isMapLoading && !_isLocationLoading && _loadingStatus.isEmpty)
            //   Positioned(
            //     right: 16,
            //     bottom: 100,
            //     child: FloatingActionButton(
            //       heroTag: "myLocation",
            //       mini: true,
            //       backgroundColor: Colors.white,
            //       elevation: 4,
            //       child: Icon(
            //         Icons.my_location,
            //         color: locationProvider.currentPosition != null
            //             ? Colors.blue
            //             : Colors.grey,
            //       ),
            //       onPressed: () async {
            //         await locationProvider.getCurrentLocationAndNavigate();
            //       },
            //     ),
            //   ),

            // Control Panel - All action buttons grouped together
            if (!_isMapLoading && !_isLocationLoading && _loadingStatus.isEmpty)
              Positioned(
                right: 16,
                bottom: 100,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Online/Offline Status Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            locationProvider.isOnline
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              locationProvider.isOnline
                                  ? Colors.green
                                  : Colors.red,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  locationProvider.isOnline
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            locationProvider.isOnline ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  locationProvider.isOnline
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Main Control Buttons
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Online/Offline Toggle Button
                          FloatingActionButton(
                            heroTag: "onlineToggle",
                            backgroundColor:
                                locationProvider.isOnline
                                    ? Colors.green
                                    : Colors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            onPressed: () async {
                              HapticFeedback.mediumImpact(); // Add haptic feedback
                              if (locationProvider.isOnline) {
                                await locationProvider.goOffline();
                              } else {
                                await locationProvider.goOnline(context);
                              }
                            },
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Icon(
                                locationProvider.isOnline
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                key: ValueKey(locationProvider.isOnline),
                                size: 28,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Hotspots Toggle Button
                          FloatingActionButton(
                            heroTag: "hotspotsToggle",
                            mini: true,
                            backgroundColor:
                                _showHotspots
                                    ? Colors.orange
                                    : Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _showHotspots = !_showHotspots;
                                _updateHotspotCircles();
                                if (_showHotspots) {
                                  _zoomToShowAllHotspots();
                                }
                              });
                            },
                            child: Stack(
                              children: [
                                Icon(Icons.local_fire_department, size: 20),
                                if (_hotspots.isNotEmpty)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 12,
                                        minHeight: 12,
                                      ),
                                      child: Text(
                                        '${_hotspots.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Refresh Hotspots Button
                          FloatingActionButton(
                            heroTag: "refreshHotspots",
                            mini: true,
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            onPressed:
                                _isLoadingHotspots
                                    ? null
                                    : () {
                                      HapticFeedback.lightImpact();
                                      _loadHotspots();
                                    },
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child:
                                  _isLoadingHotspots
                                      ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.refresh, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Quick Stats Panel (Optional)
                    if (_hotspots.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_hotspots.length} zones',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            if (_showHotspots)
                              Text(
                                'Visible',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.green[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            // Hotspot loading indicator
            if (_isLoadingHotspots)
              Positioned(
                top: 50,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      const Text('Loading hotspots...'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Center map on current location with animation
  Future<void> _centerMapOnCurrentLocation(
    LocationProvider locationProvider,
  ) async {
    if (locationProvider.currentPosition == null) return;

    final position = locationProvider.currentPosition!;
    final latitude = position.latitude;
    final longitude = position.longitude;

    if (latitude == null || longitude == null) return;

    try {
      final controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(latitude, longitude),
            zoom: 16,
            bearing: position.heading ?? 0.0,
          ),
        ),
      );
      print('Map centered on current location: $latitude, $longitude');
    } catch (e) {
      print('Error centering map on current location: $e');
    }
  }

  // Update map markers and polylines based on current state
  void _updateMapData(
    LocationProvider locationProvider,
    TripProvider tripProvider,
  ) {
    _markers.clear();
    _polylines.clear();

    // Add driver's current position marker
    if (locationProvider.currentPosition != null) {
      final position = locationProvider.currentPosition!;
      final latitude = position.latitude;
      final longitude = position.longitude;

      if (latitude != null && longitude != null) {
        final driverLatLng = LatLng(latitude, longitude);

        // Choose appropriate taxi car icon based on online status
        BitmapDescriptor markerIcon;
        if (_iconsLoaded) {
          markerIcon =
              locationProvider.isOnline
                  ? (_taxiOnlineIcon ?? BitmapDescriptor.defaultMarker)
                  : (_taxiOfflineIcon ?? BitmapDescriptor.defaultMarker);
        } else {
          // Fallback to colored default markers while icons are loading
          markerIcon = BitmapDescriptor.defaultMarkerWithHue(
            locationProvider.isOnline
                ? BitmapDescriptor
                    .hueGreen // Green for online
                : BitmapDescriptor.hueRed, // Red for offline
          );
        }

        _markers.add(
          Marker(
            markerId: const MarkerId('driver_location'),
            position: driverLatLng,
            icon: markerIcon,
            rotation:
                position.heading ??
                0.0, // Rotate taxi icon based on heading direction
            anchor: const Offset(0.5, 0.5), // Center the icon on the position
            infoWindow: InfoWindow(
              title: '🚕 Your Taxi',
              snippet:
                  locationProvider.isOnline
                      ? '✅ Online - Ready for rides'
                      : '⏸️ Offline',
            ),
          ),
        );

        // Handle active trip markers and routes
        _handleTripMarkers(tripProvider, driverLatLng);

        // Handle pickup preview marker (when dialog is minimized)
        if (tripProvider.isShowingPickupPreview &&
            tripProvider.pickupPreviewData != null) {
          final pickupData = tripProvider.pickupPreviewData!;
          final pickupLat = pickupData['latitude'] as double?;
          final pickupLng = pickupData['longitude'] as double?;
          final pickupAddress = pickupData['address'] as String?;

          if (pickupLat != null && pickupLng != null) {
            final pickupLatLng = LatLng(pickupLat, pickupLng);

            // Add pickup marker
            _markers.add(
              Marker(
                markerId: const MarkerId('pickup_preview'),
                position: pickupLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
                infoWindow: InfoWindow(
                  title: '📍 Pickup Location',
                  snippet: pickupAddress ?? 'Rider pickup point',
                ),
              ),
            );

            // Center map to show both driver and pickup
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitMapToBounds([driverLatLng, pickupLatLng]);
            });
          }
        }
      }
    }

    // Update hotspot circles
    _updateHotspotCircles();
  }

  // Handle trip-related markers and routes
  void _handleTripMarkers(TripProvider tripProvider, LatLng driverLocation) {
    if (tripProvider.currentTripData == null) return;

    final tripData = tripProvider.currentTripData!;
    final status = tripData['status'] as String?;

    if (status == null) return;

    switch (status) {
      case 'accepted':
      case 'arriving':
        _addPickupMarkerAndRoute(tripData, driverLocation);
        break;
      case 'inprogress':
        _addDropoffMarkerAndRoute(tripData, driverLocation);
        break;
      case 'completed':
        // Clear trip-related markers for completed trips
        break;
    }
  }

  // Add pickup marker and route
  void _addPickupMarkerAndRoute(
    Map<String, dynamic> tripData,
    LatLng driverLocation,
  ) {
    final pickup = tripData['pickup'];
    if (pickup == null) return;

    final pickupLatLng = LatLng(
      pickup['latitude']?.toDouble() ?? 0.0,
      pickup['longitude']?.toDouble() ?? 0.0,
    );

    _markers.add(
      Marker(
        markerId: const MarkerId('pickup_location'),
        position: pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup Location',
          snippet: pickup['address'] ?? 'Pickup Point',
        ),
      ),
    );

    // Draw route from driver to pickup
    _getDirectionsAndDrawRoute(driverLocation, pickupLatLng, 'pickup_route');

    // Fit map to show both driver and pickup
    _fitMapToBounds([driverLocation, pickupLatLng]);
  }

  // Add dropoff marker and route
  void _addDropoffMarkerAndRoute(
    Map<String, dynamic> tripData,
    LatLng driverLocation,
  ) {
    final dropoff = tripData['dropoff'];
    if (dropoff == null) return;

    final dropoffLatLng = LatLng(
      dropoff['latitude']?.toDouble() ?? 0.0,
      dropoff['longitude']?.toDouble() ?? 0.0,
    );

    _markers.add(
      Marker(
        markerId: const MarkerId('dropoff_location'),
        position: dropoffLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Dropoff Location',
          snippet: dropoff['address'] ?? 'Destination',
        ),
      ),
    );

    // Draw route from driver to dropoff
    _getDirectionsAndDrawRoute(driverLocation, dropoffLatLng, 'dropoff_route');

    // Fit map to show both driver and dropoff
    _fitMapToBounds([driverLocation, dropoffLatLng]);
  }

  // Get directions and draw route
  Future<void> _getDirectionsAndDrawRoute(
    LatLng origin,
    LatLng destination,
    String polylineId,
  ) async {
    try {
      const apiKey =
          'AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis'; // Replace with your API key

      final url =
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=driving'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      final decoded = json.decode(response.body);

      if (decoded['status'] == 'OK' && decoded['routes'].isNotEmpty) {
        final points = PolylinePoints().decodePolyline(
          decoded['routes'][0]['overview_polyline']['points'],
        );

        final polylineCoordinates =
            points
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList();

        if (mounted) {
          // Schedule setState for after current build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _polylines.add(
                  Polyline(
                    polylineId: PolylineId(polylineId),
                    color:
                        polylineId.contains('pickup')
                            ? Colors.green
                            : Colors.red,
                    points: polylineCoordinates,
                    width: 5,
                    patterns: [], // Solid line
                  ),
                );
              });
            }
          });
        }
      } else {
        // Fallback to straight line if API fails
        _drawStraightLine(origin, destination, polylineId);
      }
    } catch (e) {
      print('Error getting directions: $e');
      // Fallback to straight line
      _drawStraightLine(origin, destination, polylineId);
    }
  }

  // Draw straight line as fallback
  void _drawStraightLine(LatLng origin, LatLng destination, String polylineId) {
    if (mounted) {
      // Schedule setState for after current build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: PolylineId(polylineId),
                color:
                    polylineId.contains('pickup') ? Colors.green : Colors.red,
                points: [origin, destination],
                width: 3,
                patterns: [
                  PatternItem.dash(10),
                  PatternItem.gap(5),
                ], // Dashed line for fallback
              ),
            );
          });
        }
      });
    }
  }

  // Fit map to show all specified points
  Future<void> _fitMapToBounds(List<LatLng> points) async {
    if (points.length <= 1) return;

    try {
      final controller = await _controller.future;

      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (var point in points) {
        minLat = minLat < point.latitude ? minLat : point.latitude;
        maxLat = maxLat > point.latitude ? maxLat : point.latitude;
        minLng = minLng < point.longitude ? minLng : point.longitude;
        maxLng = maxLng > point.longitude ? maxLng : point.longitude;
      }

      // Add some padding to the bounds
      const padding = 0.001;

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - padding, minLng - padding),
            northeast: LatLng(maxLat + padding, maxLng + padding),
          ),
          150.0, // padding in pixels
        ),
      );
    } catch (e) {
      print('Error fitting map to bounds: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
