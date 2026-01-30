// lib/providers/location_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isOnline = false;
  bool _permissionGranted = false;
  StreamSubscription<Position>? _locationSubscription;
  
  // Changed from LocationData to Position
  Position? _currentPosition;
  GoogleMapController? _mapController; // Add this to store map controller

  // Getters
  bool get isOnline => _isOnline;
  bool get hasPermission => _permissionGranted;
  Position? get currentPosition => _currentPosition;

  // Constructor to initialize
  LocationProvider() {
    initialize();
  }

  // Initialize location services
  Future<void> initialize() async {
    print('🗺️ Initializing LocationProvider...');
    await _checkPermission();
    if (_permissionGranted) {
      print('🗺️ Permission granted, getting initial location...');
      // Get initial position in the background to avoid blocking
      _getCurrentLocationAndNavigate().then((_) {
        print('🗺️ Initial location retrieval completed');
      }).catchError((error) {
        print('🗺️ Error during initial location retrieval: $error');
      });
    } else {
      print('🗺️ Location permission not granted');
    }
  }

  // Get current location and automatically navigate to it
  Future<void> _getCurrentLocationAndNavigate() async {
    try {
      print('🗺️ Getting current location with geolocator...');
      
      // Check permission first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('🗺️ Location permissions denied');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('🗺️ Location permissions permanently denied');
        return;
      }
      
      // Get current position with timeout
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      if (_currentPosition != null) {
        print('🗺️ Current location obtained: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        
        // If map controller is available, animate to current position
        if (_mapController != null) {
          await _animateToCurrentPosition();
        }
        
        notifyListeners();
      }
    } on TimeoutException catch (e) {
      print('🗺️ Location timeout: $e - trying last known position...');
      await _tryLastKnownPosition();
    } on LocationServiceDisabledException {
      print('🗺️ Location services are disabled');
    } on PermissionDeniedException {
      print('🗺️ Location permissions denied');
    } catch (e) {
      print('🗺️ Error getting initial location: $e');
      await _tryLastKnownPosition();
    }
  }
  
  // Helper method to get last known position
  Future<void> _tryLastKnownPosition() async {
    try {
      _currentPosition = await Geolocator.getLastKnownPosition();
      if (_currentPosition != null) {
        print('🗺️ Using last known position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        if (_mapController != null) {
          await _animateToCurrentPosition();
        }
        notifyListeners();
      } else {
        print('🗺️ No last known position available');
      }
    } catch (e) {
      print('🗺️ Could not get last known position: $e');
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
      
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(latitude, longitude),
              zoom: 16.0, // Adjust zoom level as needed
              bearing: _currentPosition!.heading,
            ),
          ),
        );
        print('🗺️ Camera animated to current position');
      } catch (e) {
        print('🗺️ Error animating camera: $e');
      }
    }
  }

  // Public method to manually get current location and navigate
  Future<void> getCurrentLocationAndNavigate() async {
    print('🗺️ Getting current location and navigating...');
    
    if (!_permissionGranted) {
      print('🗺️ No permission, checking...');
      await _checkPermission();
      if (!_permissionGranted) {
        print('🗺️ Permission denied');
        return;
      }
    }
    
    await _getCurrentLocationAndNavigate();
  }

  // Check and request location permission
  Future<void> _checkPermission() async {
    print('🗺️ Checking location permissions...');
    
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('🗺️ Location services are disabled');
      _permissionGranted = false;
      notifyListeners();
      return;
    }

    // Check location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('🗺️ Location permissions are denied');
        _permissionGranted = false;
        notifyListeners();
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      print('🗺️ Location permissions are permanently denied');
      _permissionGranted = false;
      notifyListeners();
      return;
    }

    print('🗺️ Location permission granted');
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

      // Start location tracking with Geolocator
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen(
        (Position position) {
          _currentPosition = position;
          _updateDriverLocation(position);
          notifyListeners();
        },
        onError: (e) {
          print('🗺️ Location stream error: $e');
        },
      );

      _isOnline = true;
      notifyListeners();
      
      // Get current location when going online
      await _getCurrentLocationAndNavigate();
    } catch (e) {
      print('🗺️ Error going online: $e');
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
  Future<void> _updateDriverLocation(Position position) async {
    if (_auth.currentUser == null) return;

    try {
      final GeoPoint location = GeoPoint(position.latitude, position.longitude);

      await _firestore.collection('drivers').doc(_auth.currentUser!.uid).update({
        'location': location,
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'lastLocationUpdate': FieldValue.serverTimestamp()
      });
    } catch (e) {
      print('🗺️ Error updating location: $e');
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
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      print("🗺️ Error opening app settings: $e");
    }
  }
}