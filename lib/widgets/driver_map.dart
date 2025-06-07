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

class DriverMap extends StatefulWidget {
  const DriverMap({Key? key}) : super(key: key);

  @override
  State<DriverMap> createState() => _DriverMapState();
}

class _DriverMapState extends State<DriverMap> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Map camera position - will be updated based on current location
  CameraPosition _initialCameraPosition = const CameraPosition(
   target: LatLng(33.8938, 35.5018), // Beirut, Lebanon coordinates
    zoom: 14.0,
  );
  
  bool _mapInitialized = false;
  bool _isMapLoading = true;
  bool _isLocationLoading = true;
  String _loadingStatus = 'Loading map...';
  
  @override
  void initState() {
    super.initState();
    // Start location initialization after a short delay to let map start loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationAfterDelay();
    });
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
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      
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
    if (position?.latitude != null && position?.longitude != null && !_mapInitialized) {
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
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: false, // We'll use our custom button
              zoomControlsEnabled: true,
              compassEnabled: true,
              markers: _markers,
              polylines: _polylines,
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
            if (_isMapLoading || _isLocationLoading || _loadingStatus.isNotEmpty)
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
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
                      if (!_isMapLoading && (_isLocationLoading || _loadingStatus.isNotEmpty))
                        Column(
                          children: [
                            if (_isLocationLoading)
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
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
                                color: _loadingStatus.contains('found')
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
                                      color: !_isMapLoading ? Colors.green : Colors.blue,
                                      border: Border.all(
                                        color: !_isMapLoading ? Colors.green : Colors.blue,
                                        width: 2,
                                      ),
                                    ),
                                    child: !_isMapLoading
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      color: !_isMapLoading ? Colors.green : Colors.grey[300],
                                    ),
                                  ),
                                  // Location loading step
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: !_isLocationLoading 
                                          ? Colors.green 
                                          : _isMapLoading 
                                              ? Colors.grey[300] 
                                              : Colors.blue,
                                      border: Border.all(
                                        color: !_isLocationLoading 
                                            ? Colors.green 
                                            : _isMapLoading 
                                                ? Colors.grey[300]! 
                                                : Colors.blue,
                                        width: 2,
                                      ),
                                    ),
                                    child: !_isLocationLoading
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : !_isMapLoading
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Map',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: !_isMapLoading ? Colors.green : Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: !_isLocationLoading 
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
            
            // Custom "My Location" button (only show when loading is complete)
            if (!_isMapLoading && !_isLocationLoading && _loadingStatus.isEmpty)
              Positioned(
                right: 16,
                bottom: 100,
                child: FloatingActionButton(
                  heroTag: "myLocation",
                  mini: true,
                  backgroundColor: Colors.white,
                  elevation: 4,
                  child: Icon(
                    Icons.my_location,
                    color: locationProvider.currentPosition != null 
                        ? Colors.blue 
                        : Colors.grey,
                  ),
                  onPressed: () async {
                    await locationProvider.getCurrentLocationAndNavigate();
                  },
                ),
              ),
            
            // Online/Offline toggle button (only show when loading is complete)
            if (!_isMapLoading && !_isLocationLoading && _loadingStatus.isEmpty)
              Positioned(
                right: 16,
                bottom: 160,
                child: FloatingActionButton(
                  heroTag: "onlineToggle",
                  mini: true,
                  backgroundColor: locationProvider.isOnline ? Colors.green : Colors.red,
                  elevation: 4,
                  child: Icon(
                    locationProvider.isOnline ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () async {
                    if (locationProvider.isOnline) {
                      await locationProvider.goOffline();
                    } else {
                      await locationProvider.goOnline(context);
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
  
  // Center map on current location with animation
  Future<void> _centerMapOnCurrentLocation(LocationProvider locationProvider) async {
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
  void _updateMapData(LocationProvider locationProvider, TripProvider tripProvider) {
    _markers.clear();
    _polylines.clear();
    
    // Add driver's current position marker
    if (locationProvider.currentPosition != null) {
      final position = locationProvider.currentPosition!;
      final latitude = position.latitude;
      final longitude = position.longitude;
      
      if (latitude != null && longitude != null) {
        final driverLatLng = LatLng(latitude, longitude);
        
        _markers.add(
          Marker(
            markerId: const MarkerId('driver_location'),
            position: driverLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              locationProvider.isOnline 
                  ? BitmapDescriptor.hueBlue 
                  : BitmapDescriptor.hueViolet
            ),
            rotation: position.heading ?? 0.0,
            infoWindow: InfoWindow(
              title: 'Your Location',
              snippet: locationProvider.isOnline ? 'Online' : 'Offline',
            ),
          ),
        );
        
        // Handle active trip markers and routes
        _handleTripMarkers(tripProvider, driverLatLng);
      }
    }
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
  void _addPickupMarkerAndRoute(Map<String, dynamic> tripData, LatLng driverLocation) {
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
  void _addDropoffMarkerAndRoute(Map<String, dynamic> tripData, LatLng driverLocation) {
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
  Future<void> _getDirectionsAndDrawRoute(LatLng origin, LatLng destination, String polylineId) async {
    try {
      const apiKey = 'AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis'; // Replace with your API key
      
      final url = 'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=driving'
          '&key=$apiKey';
      
      final response = await http.get(Uri.parse(url));
      final decoded = json.decode(response.body);
      
      if (decoded['status'] == 'OK' && decoded['routes'].isNotEmpty) {
        final points = PolylinePoints().decodePolyline(
          decoded['routes'][0]['overview_polyline']['points']
        );
        
        final polylineCoordinates = points
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
                    color: polylineId.contains('pickup') ? Colors.green : Colors.red,
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
                color: polylineId.contains('pickup') ? Colors.green : Colors.red,
                points: [origin, destination],
                width: 3,
                patterns: [PatternItem.dash(10), PatternItem.gap(5)], // Dashed line for fallback
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