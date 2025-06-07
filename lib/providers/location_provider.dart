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
  GoogleMapController? _mapController; // Add this to store map controller

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
      // Get initial position and move to it
      await _getCurrentLocationAndNavigate();
    }
  }

  // Get current location and automatically navigate to it
  Future<void> _getCurrentLocationAndNavigate() async {
    try {
      print('Getting current location...');
      _currentPosition = await _location.getLocation();
      
      if (_currentPosition != null) {
        print('Current location obtained: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        
        // If map controller is available, animate to current position
        if (_mapController != null) {
          await _animateToCurrentPosition();
        }
        
        notifyListeners();
      }
    } catch (e) {
      print('Error getting initial location: $e');
    }
  }

  // Store map controller reference
  void setMapController(GoogleMapController controller) {
    _mapController = controller;
    
    // If we already have current position, animate to it
    if (_currentPosition != null) {
      _animateToCurrentPosition();
    }
  }

  // Private method to animate to current position
  Future<void> _animateToCurrentPosition() async {
    if (_mapController != null && _currentPosition != null) {
      final latitude = _currentPosition!.latitude;
      final longitude = _currentPosition!.longitude;
      
      if (latitude != null && longitude != null) {
        try {
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(latitude, longitude),
                zoom: 16.0, // Adjust zoom level as needed
                bearing: _currentPosition!.heading ?? 0.0,
              ),
            ),
          );
          print('Camera animated to current position');
        } catch (e) {
          print('Error animating camera: $e');
        }
      }
    }
  }

  // Public method to manually get current location and navigate
  Future<void> getCurrentLocationAndNavigate() async {
    if (!_permissionGranted) {
      await _checkPermission();
      if (!_permissionGranted) return;
    }
    
    await _getCurrentLocationAndNavigate();
  }

  // Check and request location permission
  Future<void> _checkPermission() async {
    bool serviceEnabled;
    PermissionStatus foregroundPermissionStatus;

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

    // Try to enable background mode
    try {
      bool backgroundEnabled = await _location.enableBackgroundMode(enable: true);
      if (!backgroundEnabled) {
        print('Background location mode could not be enabled');
      }
    } catch (e) {
      print('Error enabling background mode: $e');
    }

    // Set accuracy to high
    _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 5000,
      distanceFilter: 5,
    );

    _permissionGranted = true;
    notifyListeners();
  }

  // Go online and start sharing location
  Future<void> goOnline(BuildContext context) async {
    if (_auth.currentUser == null) return;
    
    if (!_permissionGranted) {
      await _checkPermission();
      if (!_permissionGranted) return;
    }
    
    try {
      // Update driver status in Firestore
      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'isOnline': true,
        'lastOnlineAt': FieldValue.serverTimestamp(),
        'isAvailable': true
      });

      // Start location tracking
      _locationSubscription = _location.onLocationChanged.listen((locationData) {
        _currentPosition = locationData;
        _updateDriverLocation(locationData);
        notifyListeners();
      });

      _isOnline = true;
      notifyListeners();
      
      // Get current location when going online
      await _getCurrentLocationAndNavigate();
    } catch (e) {
      print('Error going online: $e');
    }
  }

  // Go offline and stop sharing location
  Future<void> goOffline() async {
    if (_auth.currentUser == null) return;

    try {
      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'isOnline': false,
        'lastOfflineAt': FieldValue.serverTimestamp(),
        'isAvailable': false
      });

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
        'heading': locationData.heading ?? 0.0,
        'lastLocationUpdate': FieldValue.serverTimestamp()
      });
    } catch (e) {
      print('Error updating location: $e');
    }
  }
  
  // For moving the camera to current position (public method)
  Future<void> animateToCurrentPosition(GoogleMapController controller) async {
    _mapController = controller;
    await _animateToCurrentPosition();
  }

  // Add method to refresh current location
  Future<void> refreshCurrentLocation() async {
    if (!_permissionGranted) {
      await _checkPermission();
      if (!_permissionGranted) return;
    }
    
    await _getCurrentLocationAndNavigate();
  }

  // Clean up when provider is disposed
  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
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