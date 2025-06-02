// lib/providers/trip_provider.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:taxi_driver_app/main.dart';
import 'package:taxi_driver_app/screens/trip_tracker_screen.dart';

class TripProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
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
  Stream<Map<String, dynamic>> get tripRequests => _tripRequestController.stream;
  bool get hasActiveTripRequest => _currentTripId != null;
  
  // Initialize provider
  Future<void> initialize() async {
    await _checkForCurrentTrip();
  }
  
  // Check if driver has an active trip
  Future<void> _checkForCurrentTrip() async {
    if (_auth.currentUser == null) return;
    
    try {
      // Check driver_locations for current trip
      DocumentSnapshot locDoc = await _firestore
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
      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'currentTripId': tripId,
        'isAvailable': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    
    notifyListeners();
  } catch (e) {
    print('Error loading trip: $e');
  }
}
  
 // Update the acceptTrip method in TripProvider
Future<bool> acceptTrip(String tripId) async {
  if (_auth.currentUser == null) return false;
  
  try {
    // Update trip in Firestore
    await _firestore.collection('trips').doc(tripId).update({
      'status': 'driver_accepted',
      'driverId': _auth.currentUser!.uid,
      'acceptedAt': FieldValue.serverTimestamp()
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
      await _firestore.collection('trips').doc(_currentTripId).update({
        'status': 'completed',
        'completed': true,
        'completionTime': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Clear current trip
      String completedTripId = _currentTripId!;
      _currentTripId = null;
      _currentTripData = null;
      _tripSubscription?.cancel();
      
      // Update driver location to available again
      if (_auth.currentUser != null) {
        await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
          'currentTripId': null,
          'isAvailable': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      print('Error completing trip: $e');
      return false;
    }
  }
  
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
      _tripSubscription = _firestore.collection('trips').doc(tripId).snapshots().listen((snapshot) {
        if (snapshot.exists) {
          _currentTripData = {
            ...snapshot.data()!,
            'id': snapshot.id,
          };
          
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
    void rejectTrip(String tripId) {
    // Implement your logic to reject the trip
    // This should call your backend API
    print('Rejecting trip: $tripId');
  }
  
// Method to process FCM notifications
void processFcmNotification(Map<String, dynamic> messageData) {
  // Check if it's a trip request notification
  if (messageData['notificationType'] == 'tripRequest') {
    // Initialize base trip data
    final processedData = {
      'tripId': messageData['tripId'],
      'pickup': {
        'address': messageData['pickupAddress'],
        'latitude': double.tryParse(messageData['pickupLatitude'] ?? '0'),
        'longitude': double.tryParse(messageData['pickupLongitude'] ?? '0'),
      },
      'dropoff': {
        'address': messageData['dropoffAddress'],
      },
      'fare': double.tryParse(messageData['fare'] ?? '0'),
      'distance': double.tryParse(messageData['distance'] ?? '0'),
      'duration': int.tryParse(messageData['estimatedDuration'] ?? '0'),
      'expiresIn': messageData['expiresIn'],
      'totalWaitingTime': int.tryParse(messageData['totalWaitingTime'] ?? '0') ?? 0,
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
            'latitude': double.tryParse(messageData['stop${stopIndex}Latitude'] ?? '0') ?? 0.0,
            'longitude': double.tryParse(messageData['stop${stopIndex}Longitude'] ?? '0') ?? 0.0,
            'waitingTime': int.tryParse(messageData['stop${stopIndex}WaitingTime'] ?? '0') ?? 0,
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