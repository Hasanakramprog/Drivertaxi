import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';
import 'package:taxi_driver_app/services/directions_service.dart';

class TripTrackerScreen extends StatefulWidget {
  final String tripId;
  
  const TripTrackerScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  State<TripTrackerScreen> createState() => _TripTrackerScreenState();
}

class _TripTrackerScreenState extends State<TripTrackerScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  Map<String, dynamic>? _tripData;
  Timer? _locationUpdateTimer;
  final DirectionsService _directionsService = DirectionsService();
  
  // Add this field
  late TripProvider _tripProvider;
  
  @override
  void initState() {
    super.initState();
    // We can't access context in initState directly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tripProvider = Provider.of<TripProvider>(context, listen: false);
    });
    _initializeTrip();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is a safer place to access providers
    _tripProvider = Provider.of<TripProvider>(context, listen: false);
  }
  
  @override
  void dispose() {
    // Now use the stored reference instead
    _tripProvider.removeTripListener(() {
      if (mounted) {
        setState(() {
          _tripData = _tripProvider.currentTripData;
        });
        _updateRouteAndMarkers();
      }
    });
    
    _locationUpdateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
  
  Future<void> _initializeTrip() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    
    try {
      // Always load fresh trip data when screen is opened
      await tripProvider.loadTrip(widget.tripId);
      
      // Subscribe to trip updates
      tripProvider.addTripListener(() {
        if (mounted) {
          setState(() {
            _tripData = tripProvider.currentTripData;
          });
          _updateRouteAndMarkers();
        }
      });
      
      // Set initial data
      setState(() {
        _tripData = tripProvider.currentTripData;
        _isLoading = false;
      });
      
      // Start location updates
      _startLocationUpdates();
      
      // Setup initial route
      _updateRouteAndMarkers();
    } catch (e) {
      print('Error initializing trip: $e');
      setState(() {
        _isLoading = false;
      });
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load trip data: ${e.toString()}')),
      );
    }
  }
  
  void _startLocationUpdates() {
    // Update location every 5 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateRouteAndMarkers();
    });
  }
  
  Future<void> _updateRouteAndMarkers() async {
    if (_mapController == null || _tripData == null) return;
    
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final currentLocation = locationProvider.currentPosition;
    
    if (currentLocation == null) return;
    
    final tripStatus = _tripData!['status'] as String;
    final driverLatLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);
    
    // Clear existing markers and polylines
    setState(() {
      _markers = {};
      _polylines = {};
      
      // Always add driver marker
      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Your Location')
      ));
    });
    
    // If status is driver_accepted or arrived, show route to pickup
    if (tripStatus == 'driver_accepted' || tripStatus == 'driver_arrived') {
        // Access nested pickup location data
        final pickup = _tripData!['pickup'] as Map<String, dynamic>? ?? {};
        final pickupLat = double.tryParse(pickup['latitude']?.toString() ?? '') ?? 0.0;
        final pickupLng = double.tryParse(pickup['longitude']?.toString() ?? '') ?? 0.0;
        final pickupLatLng = LatLng(pickupLat, pickupLng);
        
        // Add pickup marker
        setState(() {
          _markers.add(Marker(
            markerId: const MarkerId('pickup'),
            position: pickupLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup: ${pickup['address'] ?? 'Unknown location'}')
          ));
        });
      
      // Get directions to pickup
      try {
        final directions = await _directionsService.getDirections(
          origin: driverLatLng,
          destination: pickupLatLng
        );
        
        if (directions != null) {
          setState(() {
            _polylines.add(Polyline(
              polylineId: const PolylineId('route_to_pickup'),
              color: Colors.blue,
              width: 5,
              points: directions.polylinePoints
                  .map((e) => LatLng(e.latitude, e.longitude))
                  .toList(),
            ));
          });
        }
      } catch (e) {
        print('Error getting directions: $e');
      }
      
      // Update bounds to include both driver and pickup
      _updateCameraBounds([driverLatLng, pickupLatLng]);
    }
    // If trip is in progress, show route to dropoff
    else if (tripStatus == 'in_progress') {
      final dropoff = _tripData!['dropoff'] as Map<String, dynamic>? ?? {};
      final dropoffLat = double.tryParse(dropoff['latitude']?.toString() ?? '') ?? 0.0;
      final dropoffLng = double.tryParse(dropoff['longitude']?.toString() ?? '') ?? 0.0;
      final dropoffLatLng = LatLng(dropoffLat, dropoffLng);
      
      // Add dropoff marker
      setState(() {
        _markers.add(Marker(
          markerId: const MarkerId('dropoff'),
          position: dropoffLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Dropoff: ${dropoff['address'] ?? 'Unknown destination'}')
        ));
      });
      
      // Get directions to dropoff
      try {
        final directions = await _directionsService.getDirections(
          origin: driverLatLng,
          destination: dropoffLatLng
        );
        
        if (directions != null) {
          setState(() {
            _polylines.add(Polyline(
              polylineId: const PolylineId('route_to_dropoff'),
              color: Colors.red,
              width: 5,
              points: directions.polylinePoints
                  .map((e) => LatLng(e.latitude, e.longitude))
                  .toList(),
            ));
          });
        }
      } catch (e) {
        print('Error getting directions: $e');
      }
      
      // Update bounds to include both driver and dropoff
      _updateCameraBounds([driverLatLng, dropoffLatLng]);
    }
  }
  
  void _updateCameraBounds(List<LatLng> points) {
    if (_mapController == null || points.isEmpty) return;
    
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
    
    // Add some padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );
    
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }
  
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _updateRouteAndMarkers();
  }
  
  Widget _buildTripActionButton() {
    if (_tripData == null) return const SizedBox.shrink();
    
    final tripProvider = Provider.of<TripProvider>(context);
    final status = _tripData!['status'] as String;
    
    switch (status) {
      case 'driver_accepted':
        return ElevatedButton(
          onPressed: () async {
            await tripProvider.markArrived();
            _updateRouteAndMarkers();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          child: const Text('ARRIVED AT PICKUP', style: TextStyle(fontSize: 16)),
        );
        
      case 'driver_arrived':
        return ElevatedButton(
          onPressed: () async {
            await tripProvider.startTrip();
            _updateRouteAndMarkers();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          child: const Text('START TRIP', style: TextStyle(fontSize: 16)),
        );
        
      case 'in_progress':
        return ElevatedButton(
          onPressed: () async {
            final success = await tripProvider.completeTrip();
            if (success) {
              Navigator.of(context).pop();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          child: const Text('COMPLETE TRIP', style: TextStyle(fontSize: 16)),
        );
        
      default:
        return const SizedBox.shrink();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Tracker'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(0, 0), // Will be updated immediately
                    zoom: 14,
                  ),
                  onMapCreated: _onMapCreated,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _markers,
                  polylines: _polylines,
                ),
                // Trip details panel at the top
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _buildTripStatusPanel(),
                ),
                // Action button at the bottom
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: _buildTripActionButton(),
                ),
              ],
            ),
    );
  }
  
  Widget _buildTripStatusPanel() {
    if (_tripData == null) return const SizedBox.shrink();
    
    final status = _tripData!['status'] as String;
    final statusText = _getStatusDisplayText(status);
    
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tripData!['pickupAddress'] ?? 'Unknown pickup location',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tripData!['dropoffAddress'] ?? 'Unknown destination',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status: $statusText', 
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontWeight: FontWeight.bold
                  ),
                ),
                Text(
                  'Fare: \$${_tripData!['fare'] ?? '0'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  String _getStatusDisplayText(String status) {
    switch (status) {
      case 'driver_accepted':
        return 'Driving to pickup';
      case 'driver_arrived':
        return 'Arrived at pickup';
      case 'in_progress':
        return 'Trip in progress';
      case 'completed':
        return 'Trip completed';
      default:
        return status.replaceAll('_', ' ');
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'driver_accepted':
        return Colors.blue;
      case 'driver_arrived':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}