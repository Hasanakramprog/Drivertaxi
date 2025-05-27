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
  
  // Map camera position - use a default location that will be overridden
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(37.7749, -122.4194), // Default to San Francisco if no location
    zoom: 14,
  );
  
  bool _mapInitialized = false;
  
  @override
  void initState() {
    super.initState();
    // Try to initialize the map on widget initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMapWithLocation();
    });
  }
  
  // Initialize map with location if available
  Future<void> _initializeMapWithLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentPosition != null) {
      final latitude = locationProvider.currentPosition!.latitude;
      final longitude = locationProvider.currentPosition!.longitude;
      
      if (latitude != null && longitude != null) {
        setState(() {
          _initialCameraPosition = CameraPosition(
            target: LatLng(latitude, longitude),
            zoom: 15,
          );
          _mapInitialized = true;
        });
      }
    } else {
      // Request location if not available
      await locationProvider.initialize();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer2<LocationProvider, TripProvider>(
      builder: (context, locationProvider, tripProvider, _) {
        // Initialize map with driver's current location if not done yet
        if (locationProvider.currentPosition != null && !_mapInitialized) {
          final latitude = locationProvider.currentPosition!.latitude;
          final longitude = locationProvider.currentPosition!.longitude;
          
          // Only initialize if we have valid coordinates
          if (latitude != null && longitude != null) {
            _initialCameraPosition = CameraPosition(
              target: LatLng(latitude, longitude),
              zoom: 15,
            );
            _mapInitialized = true;
          }
        }
        
        // Update markers based on the current trip and driver position
        _updateMapData(locationProvider, tripProvider);
        
        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
                // Center map on current location once controller is ready
                if (locationProvider.currentPosition != null) {
                  _centerMap(locationProvider);
                }
              },
            ),
            
            // Add a "Center on Me" button
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton(
                heroTag: "centerOnMe",
                mini: true,
                backgroundColor: Colors.white,
                child: const Icon(Icons.my_location, color: Colors.blue),
                onPressed: () {
                  _centerMap(locationProvider);
                },
              ),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _centerMap(LocationProvider locationProvider) async {
    if (locationProvider.currentPosition == null) return;
    
    final position = locationProvider.currentPosition!;
    final latitude = position.latitude;
    final longitude = position.longitude;
    
    // Only center the map if we have valid coordinates
    if (latitude == null || longitude == null) return;
    
    try {
      final controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(latitude, longitude)),
      );
    } catch (e) {
      print('Error centering map: $e');
    }
  }
  
  void _updateMapData(LocationProvider locationProvider, TripProvider tripProvider) async {
    _markers.clear();
    _polylines.clear();
    
    // Add driver's current position marker
    if (locationProvider.currentPosition != null) {
      final position = locationProvider.currentPosition!;
      final latitude = position.latitude;
      final longitude = position.longitude;
      
      // Only add marker if we have valid coordinates
      if (latitude != null && longitude != null) {
        final driverLatLng = LatLng(latitude, longitude);
        
        _markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: driverLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            rotation: position.heading ?? 0.0, // Provide default if null
          ),
        );
        
        // Check if there's an active trip
        if (tripProvider.currentTripData != null) {
          final tripData = tripProvider.currentTripData!;
          final status = tripData['status'] as String;
          
          // Add pickup marker if trip is accepted or driver is arriving
          if (['accepted', 'arriving'].contains(status)) {
            final pickup = tripData['pickup'];
            if (pickup != null) {
              final pickupLatLng = LatLng(
                pickup['latitude'] ?? 0.0,
                pickup['longitude'] ?? 0.0,
              );
              
              _markers.add(
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: pickupLatLng,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                ),
              );
              
              // Draw route from driver to pickup
              _getPolyline(driverLatLng, pickupLatLng);
              
              // Center map to show both driver and pickup
              _fitMapToBounds([driverLatLng, pickupLatLng]);
            }
          }
          
          // Add dropoff marker if trip is in progress
          if (status == 'inprogress') {
            final dropoff = tripData['dropoff'];
            if (dropoff != null) {
              final dropoffLatLng = LatLng(
                dropoff['latitude'] ?? 0.0,
                dropoff['longitude'] ?? 0.0,
              );
              
              _markers.add(
                Marker(
                  markerId: const MarkerId('dropoff'),
                  position: dropoffLatLng,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              );
              
              // Draw route from driver to dropoff
              _getPolyline(driverLatLng, dropoffLatLng);
              
              // Center map to show both driver and dropoff
              _fitMapToBounds([driverLatLng, dropoffLatLng]);
            }
          }
        }
      }
    }
  }
  
  Future<void> _getPolyline(LatLng origin, LatLng destination) async {
    try {
      // This would typically use your Google Maps Directions API key
      // For production, implement this with proper API key and error handling
      final apiKey = 'AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis';
      
      final url = 'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&key=$apiKey';
      
      final response = await http.get(Uri.parse(url));
      final decoded = json.decode(response.body);
      
      if (decoded['status'] == 'OK') {
        final points = PolylinePoints().decodePolyline(
          decoded['routes'][0]['overview_polyline']['points']
        );
        
        final List<LatLng> polylineCoordinates = points
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
        
        setState(() {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue,
              points: polylineCoordinates,
              width: 5,
            ),
          );
        });
      }
    } catch (e) {
      print('Error getting polyline: $e');
      
      // Fallback to a straight line if API fails
      setState(() {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            points: [origin, destination],
            width: 5,
          ),
        );
      });
    }
  }
  
  Future<void> _fitMapToBounds(List<LatLng> points) async {
    if (points.length <= 1) return;
    
    final controller = await _controller.future;
    
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100, // padding
      ),
    );
  }
}