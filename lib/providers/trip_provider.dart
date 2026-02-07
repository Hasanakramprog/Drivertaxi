// lib/providers/trip_provider.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_driver_app/main.dart';
import 'package:taxi_driver_app/screens/trip_tracker_screen.dart';
import 'package:taxi_driver_app/services/driver_metrics_service.dart';

class TripProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DriverMetricsService _metricsService = DriverMetricsService();

  // Current trip data
  String? _currentTripId;
  Map<String, dynamic>? _currentTripData;
  StreamSubscription? _tripSubscription;

  // Stream controller for incoming trip requests
  final StreamController<Map<String, dynamic>> _tripRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  String? get currentTripId => _currentTripId;
  Map<String, dynamic>? get currentTripData => _currentTripData;
  Stream<Map<String, dynamic>> get tripRequests =>
      _tripRequestController.stream;
  bool get hasActiveTripRequest => _currentTripId != null;

  // Add these properties
  int _currentStopIndex = -1;
  bool _hasCompletedAllStops = false;

  // Add getters
  int get currentStopIndex => _currentStopIndex;
  bool get hasCompletedAllStops => _hasCompletedAllStops;
  // Add setter methods
  Future<void> updateStopProgress(int stopIndex, bool completedAllStops) async {
    _currentStopIndex = stopIndex;
    _hasCompletedAllStops = completedAllStops;

    // Save to persistent storage
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_currentTripId != null) {
      await prefs.setInt('stop_index_${_currentTripId}', stopIndex);
      await prefs.setBool(
        'all_stops_completed_${_currentTripId}',
        completedAllStops,
      );
    }

    notifyListeners();
  }

  double? _todayEarnings;
  int? _todayTripCount;

  // Pickup preview state (for minimized dialog)
  Map<String, dynamic>? _pickupPreviewData;
  bool _isShowingPickupPreview = false;

  // Current trip request data (for re-showing dialog)
  Map<String, dynamic>? _currentTripRequest;

  // Getters
  double? get todayEarnings => _todayEarnings;
  int? get todayTripCount => _todayTripCount;
  Map<String, dynamic>? get pickupPreviewData => _pickupPreviewData;
  bool get isShowingPickupPreview => _isShowingPickupPreview;
  Map<String, dynamic>? get currentTripRequest => _currentTripRequest;

  // Methods to control pickup preview
  void showPickupPreview(Map<String, dynamic> pickupData) {
    _pickupPreviewData = pickupData;
    _isShowingPickupPreview = true;
    notifyListeners();
  }

  void hidePickupPreview() {
    _pickupPreviewData = null;
    _isShowingPickupPreview = false;
    notifyListeners();
  }

  // Methods to manage trip request
  void setCurrentTripRequest(Map<String, dynamic>? tripData) {
    _currentTripRequest = tripData;
    notifyListeners();
  }

  // Method to calculate today's earnings (call this when provider initializes)
  Future<void> _calculateTodayEarnings() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot =
          await _firestore
              .collection('trips')
              .where('driverId', isEqualTo: _auth.currentUser?.uid)
              .where('status', isEqualTo: 'completed')
              .where(
                'completionTime',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
              )
              .where('completionTime', isLessThan: Timestamp.fromDate(endOfDay))
              .get();

      double totalEarnings = 0.0;
      int tripCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
        totalEarnings += fare;
        tripCount++;
      }

      _todayEarnings = totalEarnings;
      _todayTripCount = tripCount;
      notifyListeners();
    } catch (e) {
      print('Error calculating today\'s earnings: $e');
      _todayEarnings = 0.0;
      _todayTripCount = 0;
    }
  }

  // Initialize provider
  Future<void> initialize() async {
    await _checkForCurrentTrip();
    // ...existing initialization code...
    await _calculateTodayEarnings();
  }

  // Check if driver has an active trip
  Future<void> _checkForCurrentTrip() async {
    if (_auth.currentUser == null) return;

    try {
      // Check driver_locations for current trip
      DocumentSnapshot locDoc =
          await _firestore
              .collection('driver_locations')
              .doc(_auth.currentUser!.uid)
              .get();

      if (locDoc.exists) {
        Map<String, dynamic> data = locDoc.data() as Map<String, dynamic>;
        String? tripId = data['currentTripId'];

        if (tripId != null) {
          await _loadAndListenToTrip(tripId);
        }
      }
    } catch (e) {
      print('Error checking for current trip: $e');
    }
  }

  Future<void> loadTrip(String tripId) async {
    try {
      // Cancel any existing subscription
      await _tripSubscription?.cancel();

      // Set the current trip ID
      _currentTripId = tripId;

      // Load and listen to the trip
      await _loadAndListenToTrip(tripId);

      // Update driver's current trip ID in Firestore
      if (_auth.currentUser != null) {
        await _firestore
            .collection('drivers')
            .doc(_auth.currentUser!.uid)
            .update({
              'currentTripId': tripId,
              'isAvailable': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      // Load stop progress from persistent storage
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _currentStopIndex = prefs.getInt('stop_index_${tripId}') ?? -1;
      _hasCompletedAllStops =
          prefs.getBool('all_stops_completed_${tripId}') ?? false;

      notifyListeners();
    } catch (e) {
      print('Error loading trip: $e');
    }
  }

  // Update the acceptTrip method in TripProvider
  Future<bool> acceptTrip(String tripId) async {
    if (_auth.currentUser == null) return false;

    try {
      // Update driver metrics - trip accepted
      await _metricsService.onTripAccepted(_auth.currentUser!.uid);

      // Update trip in Firestore
      await _firestore.collection('trips').doc(tripId).update({
        'status': 'driver_accepted',
        'driverId': _auth.currentUser!.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // Set as current trip
      _currentTripId = tripId;
      await _loadAndListenToTrip(tripId);

      // Navigate to trip tracker screen if context is available
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).push(
          MaterialPageRoute(
            builder: (context) => TripTrackerScreen(tripId: tripId),
          ),
        );
      }

      return true;
    } catch (e) {
      print('Error accepting trip: $e');
      return false;
    }
  }

  // Update trip status
  Future<bool> updateTripStatus(String status) async {
    if (_currentTripId == null) return false;

    try {
      await _firestore.collection('trips').doc(_currentTripId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error updating trip status: $e');
      return false;
    }
  }

  // Set trip as arrived
  Future<bool> markArrived() async {
    return await updateTripStatus('driver_arrived');
  }

  // Start trip
  Future<bool> startTrip() async {
    if (_currentTripId == null) return false;

    try {
      await _firestore.collection('trips').doc(_currentTripId).update({
        'status': 'in_progress',
        'started': true,
        'startTime': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error starting trip: $e');
      return false;
    }
  }

  // Complete trip
  Future<bool> completeTrip() async {
    if (_currentTripId == null) return false;

    try {
      // Update driver metrics - trip completed
      if (_auth.currentUser != null) {
        await _metricsService.onTripCompleted(_auth.currentUser!.uid);
      }

      // Get trip data before completing to calculate earnings
      final tripData = _currentTripData;

      await _firestore.collection('trips').doc(_currentTripId).update({
        'status': 'completed',
        'completed': true,
        'completionTime': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update today's earnings if fare is available
      if (tripData != null && tripData['fare'] != null) {
        final fare = (tripData['fare'] as num).toDouble();
        _updateTodayEarnings(fare);
      }

      // Clear current trip
      String completedTripId = _currentTripId!;
      _currentTripId = null;
      _currentTripData = null;
      _tripSubscription?.cancel();

      // Update driver location to available again
      if (_auth.currentUser != null) {
        await _firestore
            .collection('drivers')
            .doc(_auth.currentUser!.uid)
            .update({
              'currentTripId': null,
              'isAvailable': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      notifyListeners();

      // Get shared preferences instance
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_trip_id');

      // Clean up stored stop progress
      await prefs.remove('stop_index_${completedTripId}');
      await prefs.remove('all_stops_completed_${completedTripId}');

      // Reset in memory
      _currentStopIndex = -1;
      _hasCompletedAllStops = false;

      return true;
    } catch (e) {
      print('Error completing trip: $e');
      return false;
    }
  }
  /// Cancel trip after accepting (driver cancellation)
///
/// This method should be called when a driver cancels a trip after accepting it.
/// It will update metrics, Firestore, and clean up local state.
///
/// Valid cancellation reasons that don't count against metrics:
/// - 'emergency' - Personal/family emergency
/// - 'safety_concern' - Unsafe passenger/location
/// - 'passenger_no_show' - Passenger didn't appear
/// - 'vehicle_issue' - Mechanical problem
Future<bool> cancelCurrentTrip({String? reason}) async {
  if (_currentTripId == null || _auth.currentUser == null) return false;

  try {
    print('Driver cancelling trip: $_currentTripId');

    // Update driver metrics - trip cancelled
    await _metricsService.onTripCancelled(
      _auth.currentUser!.uid,
      reason: reason,
    );

    // Update trip status in Firestore
    await _firestore.collection('trips').doc(_currentTripId).update({
      'status': 'driver_cancelled',
      'cancelledBy': _auth.currentUser!.uid,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancellationReason': reason ?? 'No reason provided',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Clear current trip
    String cancelledTripId = _currentTripId!;
    _currentTripId = null;
    _currentTripData = null;
    _tripSubscription?.cancel();

    // Update driver availability
    await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
      'currentTripId': null,
      'isAvailable': true,
      'lastCancellationAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Clean up stored data
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_trip_id');
    await prefs.remove('stop_index_${cancelledTripId}');
    await prefs.remove('all_stops_completed_${cancelledTripId}');

    // Reset stop progress
    _currentStopIndex = -1;
    _hasCompletedAllStops = false;

    notifyListeners();
    print('Trip $cancelledTripId cancelled successfully');
    return true;
  } catch (e) {
    print('Error cancelling trip: $e');
    return false;
  }
}

// Usage example:
// 
// Show cancellation dialog with reasons
// final reason = await showCancellationReasonDialog();
// 
// Cancel the trip
// final success = await tripProvider.cancelCurrentTrip(reason: reason);
// 
// if (success) {
//   // Show success message
//   ScaffoldMessenger.of(context).showSnackBar(
//     SnackBar(content: Text('Trip cancelled')),
//   );
// }

  final List<Function> _tripListeners = [];

  void addTripListener(Function callback) {
    _tripListeners.add(callback);
  }

  void removeTripListener(Function callback) {
    _tripListeners.remove(callback);
  }

  // Load trip data and listen to changes
  Future<void> _loadAndListenToTrip(String tripId) async {
    // Cancel any existing subscription
    await _tripSubscription?.cancel();

    try {
      // Listen to the trip document
      _tripSubscription = _firestore
          .collection('trips')
          .doc(tripId)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists) {
              _currentTripData = {...snapshot.data()!, 'id': snapshot.id};

              // Notify listeners of data change
              notifyListeners();

              // Call all trip listeners
              for (var listener in _tripListeners) {
                listener();
              }
            } else {
              // Trip was deleted
              _currentTripId = null;
              _currentTripData = null;
              notifyListeners();
            }
          });
    } catch (e) {
      print('Error listening to trip: $e');
    }
  }

  // Get a stream of trip history
  Stream<QuerySnapshot> getTripHistory() {
    if (_auth.currentUser == null) {
      return Stream.empty();
    }

    return _firestore
        .collection('trips')
        .where('driverId', isEqualTo: _auth.currentUser!.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // Process new trip request from FCM
  void processNewTripRequest(Map<String, dynamic> data) {
    try {
      final tripId = data['tripId'];
      if (tripId == null) return;

      // Fetch trip details from Firestore
      _firestore.collection('trips').doc(tripId).get().then((doc) {
        if (doc.exists) {
          // Add to stream so UI can show the request
          _tripRequestController.add(doc.data()!);
        }
      });
    } catch (e) {
      print('Error processing trip request: $e');
    }
  }

  Future<bool> rejectTrip(String tripId) async {
    if (_auth.currentUser == null) return false;

    try {
      print('Rejecting trip: $tripId');

      // Update driver metrics - trip rejected
      await _metricsService.onTripRejected(_auth.currentUser!.uid);

      // Update trip status in Firestore
      await _firestore.collection('trips').doc(tripId).update({
        'status': 'cancelled',
        'rejectedBy': _auth.currentUser!.uid,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': 'Driver Declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update driver availability
      if (_auth.currentUser != null) {
        await _firestore
            .collection('drivers')
            .doc(_auth.currentUser!.uid)
            .update({
              'isAvailable': true,
              'currentTripId': null,
              'lastRejectionAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      // Clear current trip data if this was the active trip
      if (_currentTripId == tripId) {
        _currentTripId = null;
        _currentTripData = null;
        await _tripSubscription?.cancel();
        _tripSubscription = null;

        // Clear stored trip data
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_trip_id');
        await prefs.remove('stop_index_${tripId}');
        await prefs.remove('all_stops_completed_${tripId}');

        // Reset stop progress
        _currentStopIndex = -1;
        _hasCompletedAllStops = false;
      }

      print('Trip $tripId rejected successfully');
      notifyListeners();
      return true;
    } catch (e) {
      print('Error rejecting trip: $e');
      return false;
    }
  }

  // Reject trip with specific reason
  Future<bool> rejectTripWithReason(String tripId, String reason) async {
    if (_auth.currentUser == null) return false;

    try {
      print('Rejecting trip: $tripId with reason: $reason');

      // Update driver metrics - trip rejected
      await _metricsService.onTripRejected(_auth.currentUser!.uid);

      // Update trip status in Firestore with detailed rejection info
      await _firestore.collection('trips').doc(tripId).update({
        'status': 'driver_rejected',
        'rejectedBy': _auth.currentUser!.uid,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update driver stats for analytics
      await _firestore
          .collection('drivers')
          .doc(_auth.currentUser!.uid)
          .update({
            'isAvailable': true,
            'currentTripId': null,
            'lastRejectionAt': FieldValue.serverTimestamp(),
            'lastRejectionReason': reason,
            'totalRejections': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // Clear current trip data if this was the active trip
      if (_currentTripId == tripId) {
        _currentTripId = null;
        _currentTripData = null;
        await _tripSubscription?.cancel();
        _tripSubscription = null;

        // Clear stored trip data
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_trip_id');
        await prefs.remove('stop_index_${tripId}');
        await prefs.remove('all_stops_completed_${tripId}');

        // Reset stop progress
        _currentStopIndex = -1;
        _hasCompletedAllStops = false;
      }

      print('Trip $tripId rejected successfully with reason: $reason');
      notifyListeners();
      return true;
    } catch (e) {
      print('Error rejecting trip with reason: $e');
      return false;
    }
  }

  // Helper method to get common rejection reasons
  static List<String> getRejectionReasons() {
    return [
      'too_far',
      'going_offline',
      'personal_emergency',
      'vehicle_issue',
      'traffic_conditions',
      'other',
    ];
  }

  // Update earnings when a trip is completed
  void _updateTodayEarnings(double fare) {
    _todayEarnings = (_todayEarnings ?? 0.0) + fare;
    _todayTripCount = (_todayTripCount ?? 0) + 1;
    notifyListeners();
  }

  // Method to process FCM notifications
  void processFcmNotification(Map<String, dynamic> messageData) {
    // Check if it's a trip request notification
    if (messageData['notificationType'] == 'tripRequest') {
      // Update driver metrics - trip requested
      if (_auth.currentUser != null) {
        _metricsService.onTripRequested(_auth.currentUser!.uid);
      }

      // Initialize base trip data
      final processedData = {
        'tripId': messageData['tripId'],
        'pickup': {
          'address': messageData['pickupAddress'],
          'latitude': double.tryParse(messageData['pickupLatitude'] ?? '0'),
          'longitude': double.tryParse(messageData['pickupLongitude'] ?? '0'),
        },
        'dropoff': {'address': messageData['dropoffAddress']},
        'fare': double.tryParse(messageData['fare'] ?? '0'),
        'distance': double.tryParse(messageData['distance'] ?? '0'),
        'duration': int.tryParse(messageData['estimatedDuration'] ?? '0'),
        'expiresIn': messageData['expiresIn'],
        'totalWaitingTime':
            int.tryParse(messageData['totalWaitingTime'] ?? '0') ?? 0,
        'notificationTime':
            messageData['notificationTime'] ?? DateTime.now().toIso8601String(),
      };

      // Process stops if present
      if (messageData['hasStops'] == 'true') {
        final stopsCount = int.tryParse(messageData['stopsCount'] ?? '0') ?? 0;
        final List<Map<String, dynamic>> stops = [];

        // Process each stop (up to 5 as per backend limitation)
        final maxStops = stopsCount > 5 ? 5 : stopsCount;
        for (int i = 0; i < maxStops; i++) {
          final stopIndex = i + 1; // Backend uses 1-based indexing for stops

          // Only add if address exists
          if (messageData['stop${stopIndex}Address'] != null) {
            stops.add({
              'address': messageData['stop${stopIndex}Address'],
              'latitude':
                  double.tryParse(
                    messageData['stop${stopIndex}Latitude'] ?? '0',
                  ) ??
                  0.0,
              'longitude':
                  double.tryParse(
                    messageData['stop${stopIndex}Longitude'] ?? '0',
                  ) ??
                  0.0,
              'waitingTime':
                  int.tryParse(
                    messageData['stop${stopIndex}WaitingTime'] ?? '0',
                  ) ??
                  0,
              'index': i, // 0-based index for app usage
            });
          }
        }

        // Add stops data to processed data
        processedData['stops'] = stops;
        processedData['hasStops'] = true;
        processedData['stopsCount'] = stopsCount;

        // Check if there are additional stops not included in the message
        if (messageData['additionalStops'] != null) {
          processedData['additionalStops'] =
              int.tryParse(messageData['additionalStops'] ?? '0') ?? 0;
        } else {
          processedData['additionalStops'] = 0;
        }
      } else {
        // No stops
        processedData['hasStops'] = false;
        processedData['stops'] = <Map<String, dynamic>>[];
        processedData['stopsCount'] = 0;
        processedData['additionalStops'] = 0;
      }

      // Add the processed data to the trip requests stream
      _tripRequestController.add(processedData);
    }
  }

  @override
  void dispose() {
    _tripSubscription?.cancel();
    _tripRequestController.close();
    super.dispose();
  }
}
