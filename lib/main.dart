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
import 'package:shared_preferences/shared_preferences.dart';

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
  
  // Set up foreground message handlers
  _setupForegroundMessageHandling();
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
  
  // Get FCM token
  final token = await messaging.getToken();
  print('FCM Token: $token');
  await _updateTokenInFirestore(token);
  
  // You may want to store this token in your database associated with the driver
}
Future<void> _updateTokenInFirestore(String? token) async {
  if (token == null) return;
  
  try {
    // Import Firebase Auth and Firestore at the top of the file if not already imported
    // import 'package:firebase_auth/firebase_auth.dart';
    // import 'package:cloud_firestore/cloud_firestore.dart';
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // Update the token in the drivers collection
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser.uid)
          .update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      print('FCM token successfully updated in Firestore');
    } else {
      print('Cannot update FCM token: No user is currently logged in');
    }
  } catch (e) {
    print('Error updating FCM token: $e');
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