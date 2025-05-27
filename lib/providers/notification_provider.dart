// lib/providers/notification_provider.dart
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';

class NotificationProvider with ChangeNotifier {
  final TripProvider _tripProvider;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _initialized = false;

  NotificationProvider(this._tripProvider);

  Future<void> initialize() async {
    if (_initialized) return;

    // Request notification permissions
    await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    // Configure foreground notifications
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Handle foreground message
      print("Foreground message: ${message.data}");

      // Process trip requests or updates
      if (message.data['type'] == 'trip_request') {
        // Change to processNewTripRequest which is the correct method name
        _tripProvider.processNewTripRequest(message.data);
      }
    });

    // Set up token refresh listener
    _firebaseMessaging.onTokenRefresh.listen((String token) {
      // Update token in your backend
      _updateFcmToken(token);
    });

    // Get initial token
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      _updateFcmToken(token);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _updateFcmToken(String token) async {
    // Update token in Firestore or your backend
    print("FCM Token: $token");
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error updating FCM token: $e");
    }
  }
}