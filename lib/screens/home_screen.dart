// lib/screens/home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:taxi_driver_app/screens/about_screen.dart';

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
      // Store trip request in provider
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      tripProvider.setCurrentTripRequest(data);

      // Show trip request dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.5), // Semi-transparent barrier
        builder: (context) => TripRequestDialog(tripData: data),
      );
    }
  }

  Future<void> _checkForActiveTrip() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    // Initialize the trip provider if not already initialized
    await tripProvider.initialize();

    // Check if there's an active trip
    if (tripProvider.currentTripId != null &&
        tripProvider.currentTripData != null) {
      final tripStatus = tripProvider.currentTripData!['status'] as String?;

      // Only navigate if trip is in an active state
      if (tripStatus == 'driver_accepted' ||
          tripStatus == 'driver_arrived' ||
          tripStatus == 'in_progress') {
        // Allow the UI to fully render first
        await Future.delayed(const Duration(milliseconds: 300));

        // Navigate to trip tracker
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) =>
                      TripTrackerScreen(tripId: tripProvider.currentTripId!),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildEnhancedAppBar(),
      body: Column(
        children: [
          _buildActiveTripBanner(),
          Expanded(
            child: Stack(
              children: [
                // Map covering the whole screen
                const DriverMap(),

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

                // Enhanced Earnings FAB
                Positioned(left: 16, bottom: 16, child: _buildEarningsFAB()),

                // Minimized trip request chip (when viewing pickup on map)
                Consumer<TripProvider>(
                  builder: (context, tripProvider, _) {
                    if (tripProvider.isShowingPickupPreview &&
                        tripProvider.currentTripRequest != null) {
                      return _buildMinimizedTripChip(tripProvider);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
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
                Text(
                  'Estimated Fare: \$${tripData['fare']?.toStringAsFixed(2) ?? '0.00'}',
                ),
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
          child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  // Build minimized trip request chip
  Widget _buildMinimizedTripChip(TripProvider tripProvider) {
    final tripData = tripProvider.currentTripRequest!;
    final notificationTime =
        DateTime.tryParse(tripData['notificationTime'] ?? '') ?? DateTime.now();

    // Use TweenAnimationBuilder to trigger rebuilds every second
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 60),
      duration: const Duration(seconds: 60),
      builder: (context, value, child) {
        final elapsedSeconds =
            DateTime.now().difference(notificationTime).inSeconds;
        final remainingSeconds = (60 - elapsedSeconds).clamp(0, 60);
        final isUrgent = remainingSeconds <= 10;

        // Auto-reject when time runs out
        if (remainingSeconds <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            tripProvider.hidePickupPreview();
            tripProvider.setCurrentTripRequest(null);
            tripProvider.rejectTrip(tripData['tripId']);
          });
        }

        return Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: GestureDetector(
            onTap: () {
              // Hide pickup preview and show dialog again
              tripProvider.hidePickupPreview();
              showDialog(
                context: context,
                barrierDismissible: false,
                barrierColor: Colors.black.withOpacity(0.5),
                builder: (context) => TripRequestDialog(tripData: tripData),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors:
                      isUrgent
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : [Colors.blue.shade400, Colors.blue.shade600],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tap to view • $remainingSeconds sec',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$remainingSeconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveTripBanner() {
    final tripProvider = Provider.of<TripProvider>(context);

    // If no active trip, return empty widget
    if (tripProvider.currentTripId == null ||
        tripProvider.currentTripData == null) {
      return const SizedBox.shrink();
    }

    final tripData = tripProvider.currentTripData!;
    final status = tripData['status'] as String?;

    // Only show banner for active states
    if (status == 'driver_accepted' ||
        status == 'driver_arrived' ||
        status == 'in_progress') {
      String statusText = 'Active Trip';
      String stopInfo = '';

      // Add stop information if in progress
      if (status == 'in_progress' && tripProvider.currentStopIndex >= 0) {
        final stops = (tripData['stops'] as List<dynamic>?) ?? [];
        if (stops.isNotEmpty && !tripProvider.hasCompletedAllStops) {
          stopInfo =
              ' - Stop ${tripProvider.currentStopIndex + 1}/${stops.length}';
        } else if (tripProvider.hasCompletedAllStops) {
          stopInfo = ' - Final dropoff';
        }
      }

      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) =>
                      TripTrackerScreen(tripId: tripProvider.currentTripId!),
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

  // Add this new method for the enhanced earnings FAB
  Widget _buildEarningsFAB() {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, _) {
        // Get today's earnings (you might need to implement this in TripProvider)
        final todayEarnings = tripProvider.todayEarnings ?? 0.0;
        final tripCount = tripProvider.todayTripCount ?? 0;

        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EarningsScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 1,
                ),
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Today\'s Earnings',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '\$${todayEarnings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (tripCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$tripCount trips',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.8),
                  size: 12,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Add this new method for the enhanced AppBar
  PreferredSizeWidget _buildEnhancedAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Consumer2<LocationProvider, TripProvider>(
        builder: (context, locationProvider, tripProvider, _) {
          // Dynamic colors based on online status
          final primaryColor =
              locationProvider.isOnline ? Colors.green : Colors.red;
          final secondaryColor =
              locationProvider.isOnline
                  ? Colors.green.shade700
                  : Colors.red.shade700;

          return AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor.shade600, secondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    locationProvider.isOnline
                        ? Icons.local_taxi
                        : Icons.taxi_alert,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Taxi Driver',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            locationProvider.isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (tripProvider.todayTripCount != null &&
                              tripProvider.todayTripCount! > 0) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${tripProvider.todayTripCount} trips',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Notifications with badge
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Notifications coming soon!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      tooltip: 'Notifications',
                    ),
                    // Notification badge
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Trip History
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TripHistoryScreen(),
                      ),
                    );
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  tooltip: 'Trip History',
                ),
              ),

              // Profile Menu
              Container(
                margin: const EdgeInsets.only(right: 12),
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    HapticFeedback.lightImpact();
                    switch (value) {
                      case 'profile':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                        break;
                      case 'earnings':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EarningsScreen(),
                          ),
                        );
                        break;
                      case 'settings':
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Settings coming soon!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                        break;
                      case 'about': // Add this case
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        );
                        break;
                    }
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_circle_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  tooltip: 'Profile Menu',
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'profile',
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 20),
                              SizedBox(width: 12),
                              Text('Profile'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'earnings',
                          child: Row(
                            children: [
                              Icon(Icons.account_balance_wallet, size: 20),
                              SizedBox(width: 12),
                              Text('Earnings'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              Icon(Icons.settings, size: 20),
                              SizedBox(width: 12),
                              Text('Settings'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          // Add this menu item
                          value: 'about',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20),
                              SizedBox(width: 12),
                              Text('About'),
                            ],
                          ),
                        ),
                      ],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 8,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
