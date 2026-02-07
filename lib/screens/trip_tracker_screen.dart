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
  // Add these properties
  // int _currentStopIndex = -1; // -1 means heading to first stop or pickup
  // bool _hasCompletedAllStops = false;
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
          final oldStatus = _tripData?['status'];
          final newStatus = tripProvider.currentTripData?['status'];

          setState(() {
            _tripData = tripProvider.currentTripData;
          });

          // Initialize stop navigation when trip changes from arrived to in_progress
          if (oldStatus == 'driver_arrived' && newStatus == 'in_progress') {
            _initializeStopNavigation();
          } else {
            _updateRouteAndMarkers();
          }
        }
      });

      // Set initial data
      setState(() {
        _tripData = tripProvider.currentTripData;
        _isLoading = false;
      });

      // Initialize stop navigation if the trip is already in progress
      if (_tripData?['status'] == 'in_progress') {
        _initializeStopNavigation();
      } else {
        _updateRouteAndMarkers();
      }
    } catch (e) {
      print('Error initializing trip: $e');
      setState(() {
        _isLoading = false;
      });

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

    final locationProvider = Provider.of<LocationProvider>(
      context,
      listen: false,
    );
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final currentLocation = locationProvider.currentPosition;

    if (currentLocation == null) return;

    final tripStatus = _tripData!['status'] as String;
    final driverLatLng = LatLng(
      currentLocation.latitude ?? 0.0,
      currentLocation.longitude ?? 0.0,
    );

    // Clear existing markers and polylines
    setState(() {
      _markers = {};
      _polylines = {};

      // Always add driver marker
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });

    // If status is driver_accepted or arrived, show route to pickup
    if (tripStatus == 'driver_accepted' || tripStatus == 'driver_arrived') {
      // Access nested pickup location data
      final pickup = _tripData!['pickup'] as Map<String, dynamic>? ?? {};
      final pickupLat =
          double.tryParse(pickup['latitude']?.toString() ?? '') ?? 0.0;
      final pickupLng =
          double.tryParse(pickup['longitude']?.toString() ?? '') ?? 0.0;
      final pickupLatLng = LatLng(pickupLat, pickupLng);

      // Add pickup marker
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: pickupLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: 'Pickup: ${pickup['address'] ?? 'Unknown location'}',
            ),
          ),
        );
      });

      // Get directions to pickup
      try {
        final directions = await _directionsService.getDirections(
          origin: driverLatLng,
          destination: pickupLatLng,
        );

        if (directions != null) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route_to_pickup'),
                color: Colors.blue,
                width: 5,
                points:
                    directions.polylinePoints
                        .map((e) => LatLng(e.latitude, e.longitude))
                        .toList(),
              ),
            );
          });
        }
      } catch (e) {
        print('Error getting directions: $e');
      }

      // Update bounds to include both driver and pickup
      _updateCameraBounds([driverLatLng, pickupLatLng]);
    }
    // If trip is in progress, show route to current stop or dropoff
    else if (tripStatus == 'in_progress') {
      final dropoff = _tripData!['dropoff'] as Map<String, dynamic>? ?? {};
      final dropoffLat =
          double.tryParse(dropoff['latitude']?.toString() ?? '') ?? 0.0;
      final dropoffLng =
          double.tryParse(dropoff['longitude']?.toString() ?? '') ?? 0.0;
      final dropoffLatLng = LatLng(dropoffLat, dropoffLng);

      // Check if trip has stops
      // final hasStops = _tripData!['hasStops'] == true;
      final stops = (_tripData!['stops'] as List<dynamic>?) ?? [];

      // List to hold all points for camera bounds
      List<LatLng> boundPoints = [driverLatLng];

      // Add ALL stop and dropoff markers regardless of current destination
      if (stops.isNotEmpty) {
        // Add markers for each stop
        for (int i = 0; i < stops.length; i++) {
          final stop = stops[i] as Map<String, dynamic>;
          final stopLat =
              double.tryParse(stop['latitude']?.toString() ?? '') ?? 0.0;
          final stopLng =
              double.tryParse(stop['longitude']?.toString() ?? '') ?? 0.0;

          if (stopLat != 0.0 && stopLng != 0.0) {
            final stopLatLng = LatLng(stopLat, stopLng);
            boundPoints.add(stopLatLng);

            // Add stop marker
            setState(() {
              _markers.add(
                Marker(
                  markerId: MarkerId('stop_$i'),
                  position: stopLatLng,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    // Highlight current stop with different color
                    i == tripProvider.currentStopIndex
                        ? BitmapDescriptor.hueYellow
                        : BitmapDescriptor.hueOrange,
                  ),
                  infoWindow: InfoWindow(
                    title:
                        i == tripProvider.currentStopIndex
                            ? 'Current Stop'
                            : 'Stop ${i + 1}',
                    snippet: stop['address'] ?? 'Unknown location',
                  ),
                ),
              );
            });
          }
        }
      }

      // Add dropoff marker
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: dropoffLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              // Highlight dropoff if it's the current destination
              tripProvider.hasCompletedAllStops
                  ? BitmapDescriptor.hueYellow
                  : BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: 'Dropoff: ${dropoff['address'] ?? 'Unknown destination'}',
            ),
          ),
        );
      });

      boundPoints.add(dropoffLatLng);

      // Determine the current destination based on stop index
      LatLng destinationLatLng;
      String destinationLabel;

      if (stops.isNotEmpty &&
          tripProvider.currentStopIndex >= 0 &&
          tripProvider.currentStopIndex < stops.length) {
        // Heading to a stop
        final currentStop =
            stops[tripProvider.currentStopIndex] as Map<String, dynamic>;
        final stopLat =
            double.tryParse(currentStop['latitude']?.toString() ?? '') ?? 0.0;
        final stopLng =
            double.tryParse(currentStop['longitude']?.toString() ?? '') ?? 0.0;
        destinationLatLng = LatLng(stopLat, stopLng);
        destinationLabel =
            'Stop ${tripProvider.currentStopIndex + 1}: ${currentStop['address'] ?? 'Unknown location'}';
      } else {
        // Heading to final dropoff
        destinationLatLng = dropoffLatLng;
        destinationLabel =
            'Dropoff: ${dropoff['address'] ?? 'Unknown destination'}';
        // tripProvider.hasCompletedAllStops = true;ccc
      }

      // Get directions to current destination
      try {
        final directions = await _directionsService.getDirections(
          origin: driverLatLng,
          destination: destinationLatLng,
        );

        if (directions != null) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('current_route'),
                color: Colors.green, // Active route is green
                width: 5,
                points:
                    directions.polylinePoints
                        .map((e) => LatLng(e.latitude, e.longitude))
                        .toList(),
              ),
            );
          });
        }
      } catch (e) {
        print('Error getting directions: $e');
      }

      // Focus camera on current route section
      _updateCameraBounds([driverLatLng, destinationLatLng]);
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

  // Method to move to next stop or dropoff
  void _proceedToNextStop() async {
    if (_tripData == null) return;
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final stops = (_tripData!['stops'] as List<dynamic>?) ?? [];

    // Increment stop index
    final nextStopIndex = tripProvider.currentStopIndex + 1;
    final hasCompletedAll = nextStopIndex >= stops.length;

    // Use the provider to update and persist
    await tripProvider.updateStopProgress(nextStopIndex, hasCompletedAll);

    // Update the map
    _updateRouteAndMarkers();
  }

  // Method to initialize stop navigation
  Future _initializeStopNavigation() async {
    if (_tripData == null) return;

    // final hasStops = _tripData!['hasStops'] == true;
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final stops = (_tripData!['stops'] as List<dynamic>?) ?? [];

    // Only initialize if not already initialized
    if (tripProvider.currentStopIndex == -1 &&
        !tripProvider.hasCompletedAllStops) {
      // If there are stops, set index to first stop (0)
      // Otherwise, skip straight to dropoff
      final newStopIndex = (stops.isNotEmpty) ? 0 : -1;
      final allCompleted = stops.isEmpty;

      // Use the provider to update and persist
      await tripProvider.updateStopProgress(newStopIndex, allCompleted);
    }
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
          child: const Text(
            'ARRIVED AT PICKUP',
            style: TextStyle(fontSize: 16),
          ),
        );

      case 'driver_arrived':
        return ElevatedButton(
          onPressed: () async {
            await tripProvider.startTrip();
            _initializeStopNavigation(); // Initialize stop navigation when trip starts
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          child: const Text('START TRIP', style: TextStyle(fontSize: 16)),
        );

      case 'in_progress':
        // Check if we need to show "Complete Trip" or "Next Stop" button
        if (tripProvider.hasCompletedAllStops) {
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
        } else {
          // Get stops to show which stop we're heading to
          final stops = (_tripData!['stops'] as List<dynamic>?) ?? [];
          final nextStopNum =
              tripProvider.currentStopIndex + 1; // For display (1-based)

          return ElevatedButton(
            onPressed: () {
              _proceedToNextStop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
            child: Text(
              'COMPLETED STOP $nextStopNum',
              style: TextStyle(fontSize: 16),
            ),
          );
        }

      default:
        return const SizedBox.shrink();
    }
  }

  // Add this to your TripTrackerScreen class
  Future<bool> _onWillPop() async {
    // Only show confirmation if trip is still active
    if (_tripData != null) {
      final status = _tripData!['status'] as String;
      if (status == 'driver_accepted' ||
          status == 'driver_arrived' ||
          status == 'in_progress') {
        // Show confirmation dialog
        final result = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Return to Home?'),
                content: const Text(
                  'You can always return to track this trip from the home screen. '
                  'The trip will continue in the background.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('RETURN TO HOME'),
                  ),
                ],
              ),
        );

        return result ?? false;
      }
    }

    // If trip is completed or there's no active trip, allow navigation back
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trip Tracker'),
          actions: [
            // Cancel trip button (only show if trip is active)
            if (_tripData != null &&
                _isActiveTripStatus(_tripData!['status'] as String))
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Cancel Trip',
                onPressed: _showCancelTripDialog,
              ),
          ],
        ),
        body:
            _isLoading
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
      ),
    );
  }

  Widget _buildTripStatusPanel() {
    if (_tripData == null) return const SizedBox.shrink();

    final status = _tripData!['status'] as String;
    final statusText = _getStatusDisplayText(status);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    // Access nested pickup and dropoff data
    final pickup = _tripData!['pickup'] as Map<String, dynamic>? ?? {};
    final dropoff = _tripData!['dropoff'] as Map<String, dynamic>? ?? {};

    // Get stops info
    final stops = (_tripData!['stops'] as List<dynamic>?) ?? [];

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
                    pickup['address'] ?? 'Unknown pickup location',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),

            // Show stops if present
            if (stops.isNotEmpty) ...[
              const Divider(),
              // Current navigation status
              if (status == 'in_progress') ...[
                if (tripProvider.currentStopIndex >= 0 &&
                    tripProvider.currentStopIndex < stops.length) ...[
                  Row(
                    children: [
                      const Icon(Icons.navigation, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Navigating to Stop ${tripProvider.currentStopIndex + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (tripProvider.hasCompletedAllStops) ...[
                  Row(
                    children: [
                      const Icon(Icons.navigation, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Navigating to Dropoff',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],

            // const Divider(),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dropoff['address'] ?? 'Unknown destination',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Status: $statusText',
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Fare: \$${(_tripData!['fare'] ?? 0).toStringAsFixed(2)}',
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

  /// Check if trip status is active (can be cancelled)
  bool _isActiveTripStatus(String status) {
    return status == 'driver_accepted' ||
        status == 'driver_arrived' ||
        status == 'in_progress';
  }

  /// Show cancellation dialog with reasons
  Future<void> _showCancelTripDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Trip'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for cancellation:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildCancellationReasonTile(
                  'emergency',
                  '🚨 Emergency',
                  'Personal or family emergency',
                ),
                _buildCancellationReasonTile(
                  'safety_concern',
                  '⚠️ Safety Concern',
                  'Unsafe passenger or location',
                ),
                _buildCancellationReasonTile(
                  'passenger_no_show',
                  '👤 Passenger No-Show',
                  'Passenger did not appear',
                ),
                _buildCancellationReasonTile(
                  'vehicle_issue',
                  '🚗 Vehicle Issue',
                  'Mechanical problem',
                ),
                _buildCancellationReasonTile(
                  'other',
                  '📝 Other Reason',
                  'Other reason (will affect metrics)',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CANCEL'),
              ),
            ],
          ),
    );

    if (result != null) {
      _confirmCancellation(result);
    }
  }

  /// Build cancellation reason tile
  Widget _buildCancellationReasonTile(
    String reason,
    String title,
    String subtitle,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () => Navigator.of(context).pop(reason),
      contentPadding: EdgeInsets.zero,
    );
  }

  /// Confirm cancellation and execute
  Future<void> _confirmCancellation(String reason) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Cancellation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Are you sure you want to cancel this trip?'),
                const SizedBox(height: 12),
                if (reason == 'emergency' ||
                    reason == 'safety_concern' ||
                    reason == 'passenger_no_show' ||
                    reason == 'vehicle_issue')
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Valid reason - won\'t affect your metrics',
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This will affect your cancellation rate',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('NO, GO BACK'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('YES, CANCEL TRIP'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      _executeCancellation(reason);
    }
  }

  /// Execute the trip cancellation
  Future<void> _executeCancellation(String reason) async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await tripProvider.cancelCurrentTrip(reason: reason);

      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      if (success) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          // Return to home screen
          Navigator.of(context).pop();
        }
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel trip. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
