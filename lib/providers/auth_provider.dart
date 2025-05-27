// lib/providers/auth_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Authentication status enum
enum AuthStatus {
  loading,
  authenticated,
  unauthenticated
}

class DriverAuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  User? _user;
  bool _isInitialized = false;
  bool _isDriver = false;
  bool _isApproved = false;
  Map<String, dynamic> _driverData = {};
  AuthStatus _status = AuthStatus.loading;

  User? get user => _user;
  bool get isInitialized => _isInitialized;
  bool get isDriver => _isDriver;
  bool get isApproved => _isApproved;
  Map<String, dynamic> get driverData => _driverData;
  AuthStatus get status => _status;
  
  DriverAuthProvider() {
    initializeAuth();
  }
  
  Future<void> initializeAuth() async {
    _status = AuthStatus.loading;
    notifyListeners();
    
    _user = _auth.currentUser;
    
    if (_user != null) {
      await checkAndCreateDriverProfile();
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    
    _isInitialized = true;
    notifyListeners();
    
    // Listen for auth state changes
    _auth.authStateChanges().listen((User? user) async {
      _user = user;
      if (user != null) {
        _status = AuthStatus.authenticated;
        await checkAndCreateDriverProfile();
      } else {
        _status = AuthStatus.unauthenticated;
        _isDriver = false;
        _isApproved = false;
        _driverData = {};
      }
      notifyListeners();
    });
  }
  
  Future<void> checkAndCreateDriverProfile() async {
    try {
      DocumentSnapshot driverDoc = await _firestore
        .collection('drivers')
        .doc(_user!.uid)
        .get();
        
      if (driverDoc.exists) {
        _isDriver = true;
        _driverData = driverDoc.data() as Map<String, dynamic>;
        
        // Check approval status
        _isApproved = _driverData['isApproved'] ?? false;
      } else {
        _isDriver = false;
        _driverData = {};
      }
      
      notifyListeners();
    } catch (e) {
      print('Error checking driver profile: $e');
    }
  }
  
  Future<void> registerDriver({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required Map<String, dynamic> vehicleDetails,
  }) async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();
      
      // Create user account - wrap this in a try-catch specifically for this operation
      late UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (firebaseAuthError) {
        final User? user = userCredential.user;
        print('Firebase Auth Error: $firebaseAuthError');
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        if (firebaseAuthError is FirebaseAuthException) {
          // Return a more user-friendly message
          if (firebaseAuthError.code == 'email-already-in-use') {
            throw 'Email is already registered. Please use a different email or try logging in.';
          } else if (firebaseAuthError.code == 'weak-password') {
            throw 'Password is too weak. Please use a stronger password.';
          } else if (firebaseAuthError.code == 'invalid-email') {
            throw 'Invalid email format. Please check your email address.';
          }
        }
        throw 'Failed to create account. Please try again later.';
      }
      
      // If we get here, the account was created successfully
      final User? user = userCredential.user;
      if (user == null) {
        throw 'Account creation failed.';
      }
      
      // Update display name
      try {
        await user.updateDisplayName(fullName);
      } catch (e) {
        print('Error updating display name: $e');
        // Continue anyway - not critical
      }
      
      // Get user's FCM token for notifications
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print("Error getting FCM token: $e");
        // Continue without FCM token - can be updated later
      }
      
      // Create driver profile in Firestore
      try {
        await _firestore.collection('drivers').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'displayName': fullName,
          'phoneNumber': phoneNumber,
          'vehicleDetails': vehicleDetails,
          'isApproved': false,
          'isOnline': false,
          'isAvailable': false,
          'rating': 5.0,
          'ratingCount': 0,
          'tripCount': 0,
          'totalEarnings': 0,
          'accountStatus': 'pending',
          'documents': {
            'license': false,
            'insurance': false,
            'vehicleRegistration': false
          },
          'location': null,
          'fcmToken': fcmToken,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (firestoreError) {
        print('Firestore error creating profile: $firestoreError');
        // If Firestore fails but auth succeeded, we should clean up
        try {
          await user.delete();
        } catch (e) {
          print('Error cleaning up user after Firestore failure: $e');
        }
        throw 'Failed to create driver profile. Please try again later.';
      }
      
      await checkAndCreateDriverProfile();
      _status = AuthStatus.authenticated;
      notifyListeners();
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> loginDriver(String email, String password) async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();
      
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Auth state changes listener will handle the rest
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> logout() async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();
      
      await _auth.signOut();
      
      // Auth state changes listener will handle the rest
    } catch (e) {
      rethrow;
    }
  }
}