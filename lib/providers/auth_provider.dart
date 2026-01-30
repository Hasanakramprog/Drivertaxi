// lib/providers/auth_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  // ✅ NEW FACE VERIFICATION GETTERS
  bool get hasFaceVerificationSetup => _driverData['faceVerificationSetup'] ?? false;
  bool get isActiveToday => _driverData['isActiveToday'] ?? false;
  String get faceVerificationStatus => _driverData['faceVerificationStatus'] ?? 'pending';
  DateTime? get lastFaceVerification {
    final timestamp = _driverData['lastFaceVerification'] as Timestamp?;
    return timestamp?.toDate();
  }
  
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
          
          // ✅ FACE VERIFICATION FIELDS
          'faceVerificationSetup': true, // Set to true since they completed setup
          'lastFaceVerification': null,
          'faceVerificationStatus': 'setup_complete',
          'isActiveToday': false,
          'baseFaceImageUrl': null, // This will be set by the face verification service
          'faceVerificationHistory': [], // Array to track verification attempts
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
  
  // ✅ NEW FACE VERIFICATION METHODS
  Future<void> updateFaceVerificationStatus({
    required bool isSuccess,
    String? imageUrl,
  }) async {
    try {
      if (_user == null) return;
      
      final updateData = {
        'lastFaceVerification': FieldValue.serverTimestamp(),
        'faceVerificationStatus': isSuccess ? 'verified' : 'failed',
        'isActiveToday': isSuccess,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl != null) {
        updateData['baseFaceImageUrl'] = imageUrl;
      }
      
      // Add to verification history
      updateData['faceVerificationHistory'] = FieldValue.arrayUnion([
        {
          'timestamp': FieldValue.serverTimestamp(),
          'success': isSuccess,
          'method': 'mobile_app',
        }
      ]);
      
      await _firestore.collection('drivers').doc(_user!.uid).update(updateData);
      
      // Update local data
      _driverData.addAll(updateData);
      notifyListeners();
      
    } catch (e) {
      print('Error updating face verification status: $e');
      throw 'Failed to update verification status';
    }
  }

  Future<void> setupFaceVerification(String imageUrl) async {
    try {
      if (_user == null) return;
      
      await _firestore.collection('drivers').doc(_user!.uid).update({
        'faceVerificationSetup': true,
        'baseFaceImageUrl': imageUrl,
        'faceVerificationStatus': 'setup_complete',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update local data
      _driverData['faceVerificationSetup'] = true;
      _driverData['baseFaceImageUrl'] = imageUrl;
      _driverData['faceVerificationStatus'] = 'setup_complete';
      
      notifyListeners();
      
    } catch (e) {
      print('Error setting up face verification: $e');
      throw 'Failed to setup face verification';
    }
  }

  Future<bool> needsDailyVerification() async {
    try {
      if (_user == null) return true;
      
      // Check if setup is complete
      if (!(_driverData['faceVerificationSetup'] ?? false)) {
        return true;
      }
      
      final lastVerification = _driverData['lastFaceVerification'] as Timestamp?;
      
      if (lastVerification == null) return true;
      
      final now = DateTime.now();
      final lastVerificationDate = lastVerification.toDate();
      final difference = now.difference(lastVerificationDate);
      
      // Need verification if more than 24 hours
      return difference.inHours >= 24;
    } catch (e) {
      print('Error checking verification needs: $e');
      return true; // Default to requiring verification
    }
  }

  Future<void> refreshDriverData() async {
    if (_user != null) {
      await checkAndCreateDriverProfile();
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
      
      // Handle FCM token after successful login
      await _handleFCMTokenAfterLogin();
      
      // Auth state changes listener will handle the rest
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      rethrow;
    }
  }

  // Add this method to handle FCM token after login
  Future<void> _handleFCMTokenAfterLogin() async {
    try {
      print('Handling FCM token after login...');
      
      // Get fresh FCM token
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      
      if (token != null && _user != null) {
        print('Updating FCM token for logged in user: ${_user!.uid}');
        
        // Update token in Firestore
        await _firestore
            .collection('drivers')
            .doc(_user!.uid)
            .set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'tokenUpdatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        
        // Store locally
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_fcm_token', token);
        await prefs.remove('pending_fcm_token'); // Clear any pending token
        
        print('FCM token successfully updated after login');
      }
      
      // Also check for any pending token from before login
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('pending_fcm_token');
      if (pendingToken != null && pendingToken.isNotEmpty && pendingToken != token) {
        print('Found different pending FCM token, updating...');
        
        if (_user != null) {
          await _firestore
              .collection('drivers')
              .doc(_user!.uid)
              .set({
            'fcmToken': pendingToken,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
            'tokenUpdatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
          
          await prefs.setString('current_fcm_token', pendingToken);
          await prefs.remove('pending_fcm_token');
        }
      }
    } catch (e) {
      print('Error handling FCM token after login: $e');
    }
  }

  Future<void> logout() async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();
      
      // Set driver offline before signing out
      await _setDriverOfflineOnLogout();
      
      await _auth.signOut();
      
      // Auth state changes listener will handle the rest
    } catch (e) {
      rethrow;
    }
  }

  // Add this method to handle setting driver offline during logout
  Future<void> _setDriverOfflineOnLogout() async {
    try {
      if (_user != null) {
        print('Setting driver offline before logout...');
        
        // Update driver status in Firestore
        await _firestore.collection('drivers').doc(_user!.uid).set({
          'isOnline': false,
          'isAvailable': false,
          'lastOfflineAt': FieldValue.serverTimestamp(),
          'offlineReason': 'logout',
          'fcmToken': null, // Clear FCM token on logout for security
          'lastLocation': null, // Clear location data for privacy
        }, SetOptions(merge: true));
        
        // Clear local FCM token storage
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('current_fcm_token');
        await prefs.remove('pending_fcm_token');
        
        // Clear any active trip data
        await prefs.remove('active_trip_id');
        
        print('Driver set offline successfully');
      }
    } catch (e) {
      print('Error setting driver offline during logout: $e');
      // Continue with logout even if this fails
    }
  }

  // Add this method to your DriverAuthProvider class
  Future<void> registerDriverWithFaceVerification({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required Map<String, dynamic> vehicleDetails,
    required String faceVerificationImageUrl, // The stored URL
  }) async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();
      
      // Create user account first
      late UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (firebaseAuthError) {
        print('Firebase Auth Error: $firebaseAuthError');
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        if (firebaseAuthError is FirebaseAuthException) {
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
      
      final User? user = userCredential.user;
      if (user == null) {
        throw 'Account creation failed.';
      }
      
      // Update display name
      try {
        await user.updateDisplayName(fullName);
      } catch (e) {
        print('Error updating display name: $e');
      }
      
      // Get FCM token
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print("Error getting FCM token: $e");
      }
      
      // Create driver profile with face verification URL
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
          
          // ✅ Face verification fields with the stored URL
          'faceVerificationSetup': true,
          'lastFaceVerification': null,
          'faceVerificationStatus': 'setup_complete',
          'isActiveToday': false,
          'baseFaceImageUrl': faceVerificationImageUrl, // ✅ Use the stored URL
          'faceVerificationHistory': [],
        });
      } catch (firestoreError) {
        print('Firestore error creating profile: $firestoreError');
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
}