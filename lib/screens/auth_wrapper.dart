import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:taxi_driver_app/screens/authentication/login_screen.dart';
import 'package:taxi_driver_app/screens/home_screen.dart';
import 'package:taxi_driver_app/screens/face_verification_screen.dart';
import 'package:taxi_driver_app/screens/trip_tracker_screen.dart';
import 'package:taxi_driver_app/services/face_verification_service.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';
import 'dart:async'; // Add this import

// FEATURE FLAGS
const bool ENABLE_FACE_VERIFICATION = false; // Set to true to enable face verification

class AuthWrapper extends StatefulWidget {
  final String? initialTripId;
  
  const AuthWrapper({Key? key, this.initialTripId}) : super(key: key);
  
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isCheckingVerification = false;
  bool _needsVerification = false;
  Timer? _verificationTimer;
  DateTime? _lastVerificationCheck;
  
  @override
  void initState() {
    super.initState();
    
    // Add lifecycle observer to detect app state changes
    WidgetsBinding.instance.addObserver(this);
    
    // Check for pending trip and face verification after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialState();
    });
    
    // Start periodic verification check
    _startPeriodicVerificationCheck();
  }
  
  @override
  void dispose() {
    // Clean up timer and observer
    _verificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground, check verification (if enabled)
        if (ENABLE_FACE_VERIFICATION) {
          print('App resumed, checking face verification status');
          _checkFaceVerificationStatus();
        } else {
          print('App resumed, face verification disabled');
        }
        break;
      case AppLifecycleState.paused:
        // App went to background
        print('App paused');
        break;
      case AppLifecycleState.inactive:
        // App became inactive
        break;
      case AppLifecycleState.detached:
        // App is detached
        break;
      case AppLifecycleState.hidden:
        // App is hidden
        break;
    }
  }
  
  // Start periodic timer to check verification status
  void _startPeriodicVerificationCheck() {
    // Check feature flag first
    if (!ENABLE_FACE_VERIFICATION) {
      print('Face verification periodic check disabled via feature flag');
      return;
    }
    
    // Check every 30 minutes
    _verificationTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      print('Periodic face verification check triggered');
      _checkFaceVerificationStatus();
    });
  }
  
  Future<void> _checkInitialState() async {
    // First handle any pending trip navigation
    if (widget.initialTripId != null) {
      await _handleInitialTrip(widget.initialTripId!);
    }
    
    // Then check face verification status
    await _checkFaceVerificationStatus();
  }
  
  Future<void> _handleInitialTrip(String tripId) async {
    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      await tripProvider.initialize();
      await tripProvider.loadTrip(tripId);
      
      // Navigate to trip tracker with the active trip
      if (mounted && tripProvider.currentTripData != null) {
        final status = tripProvider.currentTripData!['status'];
        if (status == 'driver_accepted' || status == 'driver_arrived' || 
            status == 'in_progress') {
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TripTrackerScreen(tripId: tripId),
            ),
          );
        }
      }
    } catch (e) {
      print('Error handling initial trip: $e');
    }
  }
  
  Future<void> _checkFaceVerificationStatus() async {
    // Check feature flag first
    if (!ENABLE_FACE_VERIFICATION) {
      print('Face verification is disabled via feature flag');
      return;
    }
    
    if (!mounted) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Prevent multiple simultaneous checks
    if (_isCheckingVerification) {
      print('Face verification check already in progress, skipping');
      return;
    }
    
    // Check if we recently verified (within last 5 minutes) to avoid spam
    final now = DateTime.now();
    if (_lastVerificationCheck != null && 
        now.difference(_lastVerificationCheck!).inMinutes < 1) {
      print('Face verification checked recently, skipping');
      return;
    }
    
    setState(() {
      _isCheckingVerification = true;
    });
    
    try {
      print('Checking face verification status...');
      
      // Check SharedPreferences first for quick response
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final needsVerificationFromPrefs = prefs.getBool('needs_face_verification') ?? false;
      
      // Also check with the service for accurate status
      final faceService = FaceVerificationService();
      final needsVerificationFromService = await faceService.needsDailyVerification();
      
      final needsVerification = needsVerificationFromPrefs || needsVerificationFromService;
      
      print('Face verification needed: $needsVerification');
      
      // Update last check time
      _lastVerificationCheck = now;
      
      if (mounted) {
        setState(() {
          _needsVerification = needsVerification;
          _isCheckingVerification = false;
        });
        
        // If verification is needed and dialog is not already showing, show it
        if (needsVerification && !_isVerificationDialogShowing()) {
          print('Showing face verification dialog');
          _showFaceVerificationScreen();
        }
      }
    } catch (e) {
      print('Error checking face verification status: $e');
      if (mounted) {
        setState(() {
          _isCheckingVerification = false;
        });
      }
    }
  }
  
  // Check if verification dialog is already showing
  bool _isVerificationDialogShowing() {
    return ModalRoute.of(context)?.settings.name == '/face_verification_dialog';
  }
  
  void _showFaceVerificationScreen() {
  // Prevent showing multiple dialogs
  if (_isVerificationDialogShowing()) {
    print('Face verification dialog already showing');
    return;
  }
  
  showDialog(
    context: context,
    barrierDismissible: false, // Can't dismiss without verification
    routeSettings: const RouteSettings(name: '/face_verification_dialog'), // Add route name for tracking
    builder: (context) => WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.orange),
            SizedBox(width: 8),
            Expanded( // ✅ Add Expanded to prevent overflow
              child: Text(
                'Daily Verification Required',
                style: TextStyle(fontSize: 16), // ✅ Reduce font size if needed
              ),
            ),
          ],
        ),
        content: SingleChildScrollView( // ✅ Add scroll capability
          child: ConstrainedBox( // ✅ Add constraints
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.face,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'You need to complete your daily face verification to continue using the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14), // ✅ Slightly smaller text
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity, // ✅ Take full available width
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'This verification expires every 24 hours for security purposes.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox( // ✅ Constrain button width
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                
                // Navigate to face verification screen
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const FaceVerificationScreen(isSetup: false),
                  ),
                );
                
                if (result == true) {
                  // Verification successful, clear the flag
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('needs_face_verification', false);
                  
                  setState(() {
                    _needsVerification = false;
                  });
                  
                  // Show success message
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Face verification completed! You can now continue using the app.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } else {
                  // Verification failed or cancelled, show dialog again after a delay
                  await Future.delayed(const Duration(seconds: 2));
                  if (mounted && !_isVerificationDialogShowing()) {
                    print('Face verification failed, showing dialog again');
                    _showFaceVerificationScreen();
                  }
                }
              },
              icon: const Icon(Icons.face),
              label: const Text('Start Verification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (snapshot.hasData) {
          // User is logged in
          if (_isCheckingVerification) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Checking verification status...'),
                  ],
                ),
              ),
            );
          }
          
          return const HomeScreen();
        } else {
          // User is not logged in
          return const LoginScreen();
        }
      },
    );
  }
}