// lib/providers/location_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isOnline = false;
  bool _permissionGranted = false;
  Location _location = Location();
  StreamSubscription? _locationSubscription;
  
  // Add this to store the current position
  LocationData? _currentPosition;

  // Getters
  bool get isOnline => _isOnline;
  bool get hasPermission => _permissionGranted;
  LocationData? get currentPosition => _currentPosition;

  // Constructor to initialize
  LocationProvider() {
    initialize();
  }

  // Initialize location services
  Future<void> initialize() async {
    await _checkPermission();
    if (_permissionGranted) {
      // Get initial position
      try {
        _currentPosition = await _location.getLocation();
        notifyListeners();
      } catch (e) {
        print('Error getting initial location: $e');
      }
    }
  }

  // Check and request location permission
  Future<void> _checkPermission() async {
    bool serviceEnabled;
    PermissionStatus foregroundPermissionStatus;
    PermissionStatus backgroundPermissionStatus;

    // Check if location service is enabled
    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        _permissionGranted = false;
        notifyListeners();
        return;
      }
    }

    // Check foreground location permission
    foregroundPermissionStatus = await _location.hasPermission();
    if (foregroundPermissionStatus == PermissionStatus.denied) {
      foregroundPermissionStatus = await _location.requestPermission();
      if (foregroundPermissionStatus != PermissionStatus.granted) {
        _permissionGranted = false;
        notifyListeners();
        return;
      }
    }

    // Try to enable background mode (this will show the system dialog for background permission)
    try {
      bool backgroundEnabled = await _location.enableBackgroundMode(enable: true);
      if (!backgroundEnabled) {
        // If background mode couldn't be enabled, we should inform the user
        print('Background location mode could not be enabled');
      }
    } catch (e) {
      print('Error enabling background mode: $e');
      // We should still continue even if background permission is denied
      // The app will work in foreground at least
    }

    // Set accuracy to high (for better location tracking)
    _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 5000,  // Update interval in milliseconds
      distanceFilter: 5, // Minimum distance in meters to trigger update
    );

    _permissionGranted = true;
    notifyListeners();
  }

  // Go online and start sharing location
  Future<void> goOnline(BuildContext context) async {
    if (_auth.currentUser == null) return;
    
    // Check permissions first
    if (!_permissionGranted) {
      await _checkPermission();
      if (!_permissionGranted) return;
    }

    // // Specifically check background mode
    // bool backgroundEnabled = false;
    // try {
    //   backgroundEnabled = await _location.enableBackgroundMode(enable: true);
    // } catch (e) {
    //   // Permission was denied
    //   print("Background permission denied: $e");
    //   // Ask user to grant permission via settings
    //   requestBackgroundPermission(context);
    //   return;
    // }
    
    // Only proceed if we have background permission or user chose to continue anyway
    try {
      // Update driver status in Firestore
      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'isOnline': true,
        'lastOnlineAt': FieldValue.serverTimestamp(),
        'isAvailable': true
      });

      // Start location tracking
      _locationSubscription = _location.onLocationChanged.listen((locationData) {
        // Update the current position property
        _currentPosition = locationData;
        // Update the location in Firestore
        _updateDriverLocation(locationData);
        // Notify listeners so UI reflects the changes
        notifyListeners();
      });

      _isOnline = true;
      notifyListeners();
    } catch (e) {
      print('Error going online: $e');
    }
  }

  // Go offline and stop sharing location
  Future<void> goOffline() async {
    if (_auth.currentUser == null) return;

    try {
      // Update driver status in Firestore
      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'isOnline': false,
        'lastOfflineAt': FieldValue.serverTimestamp(),
        'isAvailable': false
      });

      // Stop location updates
      await _locationSubscription?.cancel();
      _locationSubscription = null;

      _isOnline = false;
      notifyListeners();
    } catch (e) {
      print('Error going offline: $e');
    }
  }

  // Update driver location in Firestore
  Future<void> _updateDriverLocation(LocationData locationData) async {
    if (_auth.currentUser == null) return;
    
    // Check if latitude and longitude are not null
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    
    if (latitude == null || longitude == null) {
      print('Location data is incomplete');
      return;
    }

    try {
      final GeoPoint location = GeoPoint(latitude, longitude);

      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'location': location,
        'heading': locationData.heading ?? 0.0, // Provide default if null
        'lastLocationUpdate': FieldValue.serverTimestamp()
      });
    } catch (e) {
      print('Error updating location: $e');
    }
  }
  
  // For moving the camera to current position
  Future<void> animateToCurrentPosition(GoogleMapController controller) async {
    if (_currentPosition != null) {
      final latitude = _currentPosition!.latitude;
      final longitude = _currentPosition!.longitude;
      
      // Only proceed if we have valid coordinates
      if (latitude != null && longitude != null) {
        controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(latitude, longitude)),
        );
      }
    }
  }

  // Add this method to your LocationProvider class
  Future<void> requestBackgroundPermission(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Background Location Permission'),
          content: const Text(
            'This app needs background location access to track your position while you drive. '
            'Please grant "Allow all the time" permission in the next screen.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                _openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAppSettings() async {
    await _location.requestService();
    // This often triggers the permission dialog or takes user to settings
    try {
      await _location.requestPermission();
    } catch (e) {
      print("Error requesting permission: $e");
    }
  }
}