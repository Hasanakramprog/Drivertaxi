// lib/screens/home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';
import 'package:taxi_driver_app/screens/earnings_screen.dart';
import 'package:taxi_driver_app/screens/profile_screen.dart';
import 'package:taxi_driver_app/screens/trip_history_screen.dart';
import 'package:taxi_driver_app/widgets/driver_map.dart';
import 'package:taxi_driver_app/widgets/online_toggle.dart';
import 'package:taxi_driver_app/widgets/trip_request_dialog.dart';
import 'package:taxi_driver_app/screens/trip_tracker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  
  @override
  void initState() {
    super.initState();
    // Initialize providers
    Future.microtask(() async {
      Provider.of<LocationProvider>(context, listen: false).initialize();
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      tripProvider.initialize();
      
      // Check for pending trip requests
      await _checkPendingTripRequests(tripProvider);
      
      // Listen for new trip requests
      tripProvider.tripRequests.listen(_handleTripRequest);
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForActiveTrip();
    });
  }

  Future<void> _checkPendingTripRequests(TripProvider tripProvider) async {
    // Retrieve any stored trip requests
    final pendingRequest = await _getPendingTripRequest();
    
    if (pendingRequest != null) {
      // Clear the stored request first to prevent showing it multiple times
      await _clearPendingTripRequest();
      
      // Process the pending request
      tripProvider.processFcmNotification(pendingRequest);
    }
  }

  Future<Map<String, dynamic>?> _getPendingTripRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedData = prefs.getString('pendingTripRequest');
      
      if (storedData != null) {
        return jsonDecode(storedData) as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error retrieving pending trip request: $e');
    }
    return null;
  }

  Future<void> _clearPendingTripRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingTripRequest');
  }

  void _handleTripRequest(Map<String, dynamic> data) {
    // Make sure we're not showing duplicate dialogs
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      // Show trip request dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => TripRequestDialog(tripData: data),
      );
    }
  }
  
  Future<void> _checkForActiveTrip() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    
    // Initialize the trip provider if not already initialized
    await tripProvider.initialize();
    
    // Check if there's an active trip
    if (tripProvider.currentTripId != null && tripProvider.currentTripData != null) {
      final tripStatus = tripProvider.currentTripData!['status'] as String?;
      
      // Only navigate if trip is in an active state
      if (tripStatus == 'driver_accepted' || tripStatus == 'driver_arrived' || 
          tripStatus == 'in_progress') {
        
        // Allow the UI to fully render first
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Navigate to trip tracker
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TripTrackerScreen(
                tripId: tripProvider.currentTripId!,
              ),
            ),
          );
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxi Driver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveTripBanner(), // Add this at the top
          Expanded(
            child: Stack(
              children: [
                // Map covering the whole screen
                const DriverMap(),
                
                // Online/Offline toggle at the top
                const Positioned(
                  top: 16.0,
                  left: 16.0,
                  right: 16.0,
                  child: OnlineToggle(),
                ),
                
                // Trip info card if there's an active trip
                Consumer<TripProvider>(
                  builder: (context, tripProvider, _) {
                    if (tripProvider.hasActiveTripRequest) {
                      return Positioned(
                        bottom: 16.0,
                        left: 16.0,
                        right: 16.0,
                        child: _buildActiveTripCard(tripProvider),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          // FAB for earnings
          FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EarningsScreen()),
              );
            },
            child: const Icon(Icons.attach_money),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActiveTripCard(TripProvider tripProvider) {
    final tripData = tripProvider.currentTripData;
    if (tripData == null) return const SizedBox.shrink();
    
    final status = tripData['status'] as String;
    
    return Card(
      elevation: 6.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getTripStatusText(status),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18.0,
              ),
            ),
            const Divider(),
            _buildAddressRow('Pickup', tripData['pickup']['address']),
            const SizedBox(height: 8.0),
            _buildAddressRow('Dropoff', tripData['dropoff']['address']),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Fare: \$${tripData['fare']?.toStringAsFixed(2) ?? '0.00'}'),
                _buildActionButton(status, tripProvider),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAddressRow(String label, String address) {
    return Row(
      children: [
        SizedBox(
          width: 80.0,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  Widget _buildActionButton(String status, TripProvider tripProvider) {
    switch (status) {
      case 'driver_accepted':
        return ElevatedButton(
          onPressed: () => tripProvider.markArrived(),
          child: const Text('ARRIVED'),
        );
      case 'driver_arrived':
        return ElevatedButton(
          onPressed: () => tripProvider.startTrip(),
          child: const Text('START TRIP'),
        );
      case 'completed':
        return ElevatedButton(
          onPressed: () => tripProvider.completeTrip(),
          child: const Text('COMPLETE'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
  
  String _getTripStatusText(String status) {
    switch (status) {
      case 'driver_accepted':
        return 'Heading to Pickup';
      case 'driver_arrived':
        return 'At Pickup Location';
      case 'in_progress':
        return 'Trip in Progress';
      case 'completed':
        return 'Trip Completed';
      default:
        return 'Trip Status: $status';
    }
  }
  
  Widget _buildActiveTripBanner() {
    final tripProvider = Provider.of<TripProvider>(context);
    
    // If no active trip, return empty widget
    if (tripProvider.currentTripId == null || tripProvider.currentTripData == null) {
      return const SizedBox.shrink();
    }
    
    final tripData = tripProvider.currentTripData!;
    final status = tripData['status'] as String?;
    
    // Only show banner for active states
    if (status == 'driver_accepted' || status == 'driver_arrived' || status == 'in_progress') {
      String statusText = 'Active Trip';
      String stopInfo = '';
      
      // Add stop information if in progress
      if (status == 'in_progress' && tripProvider.currentStopIndex >= 0) {
        final stops = (tripData['stops'] as List<dynamic>?) ?? [];
        if (stops.isNotEmpty && !tripProvider.hasCompletedAllStops) {
          stopInfo = ' - Stop ${tripProvider.currentStopIndex + 1}/${stops.length}';
        } else if (tripProvider.hasCompletedAllStops) {
          stopInfo = ' - Final dropoff';
        }
      }
      
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TripTrackerScreen(
                tripId: tripProvider.currentTripId!,
              ),
            ),
          );
        },
        child: Container(
          // Banner styling
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          color: Colors.green.withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resume Trip$stopInfo',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Text(
                'CONTINUE',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.green,
                size: 12,
              ),
            ],
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}