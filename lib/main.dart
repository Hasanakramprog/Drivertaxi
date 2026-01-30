// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';
import 'package:taxi_driver_app/providers/notification_provider.dart';
import 'package:taxi_driver_app/screens/auth_wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_driver_app/services/face_verification_service.dart';

// FEATURE FLAGS
const bool ENABLE_FACE_VERIFICATION = false; // Set to true to enable face verification

// Define the global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
   _handleFcmMessage(message);
}
// Common message handling logic for both background and foreground
void _handleFcmMessage(RemoteMessage message) {
  print('Message data: ${message.data}');
  
  // Handle trip updates
  if (message.data['notificationType'] == 'tripUpdate') {
    final tripId = message.data['tripId'];
    if (tripId != null) {
      // Save the trip ID for when app is reopened
      _saveActiveTrip(tripId);
      
      // If app is in foreground, navigate to trip
      if (navigatorKey.currentContext != null) {
        final tripProvider = Provider.of<TripProvider>(
          navigatorKey.currentContext!,
          listen: false
        );
        tripProvider.loadTrip(tripId);
      }
    }
  }
  
  if (message.notification != null) {
    print('Message notification: ${message.notification!.title}, ${message.notification!.body}');
  }
  
  // Handle different message types based on the data
  final data = message.data;
  
  // Check if it's a trip request notification
  if (data['notificationType'] == 'tripRequest') {
    // Only attempt to process if context is available (app is running)
    if (navigatorKey.currentContext != null) {
      final tripProvider = Provider.of<TripProvider>(
        navigatorKey.currentContext!,
        listen: false
      );
      tripProvider.processFcmNotification(data);
    } else {
      // Store for later processing when app opens
      _storeTripRequest(data);
    }
  }
}

// Add this function to store trip requests when app is not running
Future<void> _storeTripRequest(Map<String, dynamic> data) async {
  // Implementation using shared preferences
  // You'll need to add the shared_preferences package to your pubspec.yaml
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pendingTripRequest', jsonEncode(data));
  print("Storing trip request for later: $data");
}

Future<void> _saveActiveTrip(String tripId) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('active_trip_id', tripId);
}
// Add this function after _setupForegroundMessageHandling()
Future<void> _checkDailyVerification() async {
  // Check feature flag first
  if (!ENABLE_FACE_VERIFICATION) {
    print('Face verification is disabled via feature flag');
    return;
  }
  
  final faceService = FaceVerificationService();
  
  // Check if verification is needed
  if (await faceService.needsDailyVerification()) {
    // Store a flag that verification is needed
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('needs_face_verification', true);
  }
}

// Periodic token refresh for long-running apps
void _startPeriodicTokenRefresh() {
  // Refresh token every 6 hours to ensure it's always up to date
  Timer.periodic(const Duration(hours: 6), (timer) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      print('Periodic FCM token refresh triggered');
      
      try {
        final messaging = FirebaseMessaging.instance;
        final token = await messaging.getToken();
        
        if (token != null) {
          await _updateTokenInFirestore(token);
          print('Periodic FCM token refresh completed');
        }
      } catch (e) {
        print('Error during periodic FCM token refresh: $e');
      }
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Check for saved active trip
  SharedPreferences prefs = await SharedPreferences.getInstance();
  final activeTripId = prefs.getString('active_trip_id'); 
  // Set up FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // Request notification permissions
  await _requestNotificationPermissions();
  
  // Start periodic token refresh
  _startPeriodicTokenRefresh();
  
  // Set up foreground message handlers
  _setupForegroundMessageHandling();
  // Check daily verification status (controlled by feature flag)
  await _checkDailyVerification();
  runApp(MyApp(initialTripId: activeTripId));
}
Future<void> _requestNotificationPermissions() async {
  final messaging = FirebaseMessaging.instance;
  
  // Request permission
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  
  print('User notification permission status: ${settings.authorizationStatus}');
  
  // Setup token refresh listener - this is the key improvement!
  messaging.onTokenRefresh.listen((newToken) {
    print('FCM Token refreshed: $newToken');
    _updateTokenInFirestore(newToken);
  });
  
  // Get initial FCM token (but don't save it here if user not logged in)
  final token = await messaging.getToken();
  print('Initial FCM Token: $token');
  
  // Only save if user is already logged in, otherwise save it in AuthProvider
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await _updateTokenInFirestore(token);
  } else {
    // Store token locally for when user logs in
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_fcm_token', token ?? '');
    print('Stored FCM token for later use after login');
  }
}
Future<void> _updateTokenInFirestore(String? token) async {
  if (token == null || token.isEmpty) return;
  
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // Update the token in the drivers collection
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser.uid)
          .set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'tokenUpdatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true)); // Use merge to avoid overwriting other data
      
      print('FCM token successfully updated in Firestore for user: ${currentUser.uid}');
      
      // Also store locally for quick access
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_fcm_token', token);
      
    } else {
      print('Cannot update FCM token: No user is currently logged in');
      // Store locally for when user logs in
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_fcm_token', token);
    }
  } catch (e) {
    print('Error updating FCM token: $e');
    // Store locally as backup
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_fcm_token', token);
  }
}

// Add this function to handle token updates when user logs in
Future<void> handlePendingFCMToken() async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final pendingToken = prefs.getString('pending_fcm_token');
    
    if (pendingToken != null && pendingToken.isNotEmpty) {
      print('Processing pending FCM token after login');
      await _updateTokenInFirestore(pendingToken);
      // Clear the pending token
      await prefs.remove('pending_fcm_token');
    }
    
    // Also get fresh token in case it changed
    final messaging = FirebaseMessaging.instance;
    final currentToken = await messaging.getToken();
    if (currentToken != null && currentToken != pendingToken) {
      print('Getting fresh FCM token after login');
      await _updateTokenInFirestore(currentToken);
    }
  } catch (e) {
    print('Error handling pending FCM token: $e');
  }
}
void _setupForegroundMessageHandling() {
  // Handle messages received while the app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    _handleFcmMessage(message);
    
    // You can also show a local notification here if needed
    // This is useful for immediate visual feedback when the app is open
  });

  // Handle when the user taps on a notification that opened the app
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('A notification was tapped to open the app!');
    _handleFcmMessage(message);
    
    // You can navigate to specific screens based on the notification
    // For example:
    if (message.data['screen'] == 'trip_details') {
      final tripId = message.data['trip_id'];
      // Use the navigator key to navigate to the trip details screen
      navigatorKey.currentState?.pushNamed('/trip-details', arguments: tripId);
    }
  });
}
class MyApp extends StatelessWidget {
  final String? initialTripId;
  
  const MyApp({Key? key, this.initialTripId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverAuthProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProxyProvider<TripProvider, NotificationProvider>(
          create: (context) => NotificationProvider(
            Provider.of<TripProvider>(context, listen: false),
          ),
          update: (context, tripProvider, previous) {
            final provider = previous ?? NotificationProvider(tripProvider);
            // Initialize the notification provider
            provider.initialize();
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        // Set the navigator key here
        navigatorKey: navigatorKey,
        title: 'Taxi Driver',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        debugShowCheckedModeBanner: false,
         home: AuthWrapper(initialTripId: initialTripId),
      ),
    );
  }
}