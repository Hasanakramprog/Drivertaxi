# Taxi Driver App - AI Agent Guidelines

## Project Overview
Flutter-based taxi driver companion app with Firebase backend. Drivers receive trip requests, navigate trips with multiple stops, and manage earnings. The app uses Provider pattern for state management and Firebase Cloud Messaging for real-time notifications.

## Architecture

### State Management (Provider Pattern)
- **DriverAuthProvider** ([lib/providers/auth_provider.dart](lib/providers/auth_provider.dart)): Authentication, driver profile, face verification status
- **TripProvider** ([lib/providers/trip_provider.dart](lib/providers/trip_provider.dart)): Active trips, trip history, stop-by-stop navigation, earnings calculation
- **LocationProvider** ([lib/providers/location_provider.dart](lib/providers/location_provider.dart)): GPS tracking, online/offline status, driver location updates to Firestore
- **NotificationProvider** ([lib/providers/notification_provider.dart](lib/providers/notification_provider.dart)): FCM token management, notification handling

All providers use `ChangeNotifier` and are registered in [lib/main.dart](lib/main.dart) via `MultiProvider`.

### Firebase Collections Schema
- **`drivers`**: Driver profiles, online status, location (`geopoint`), face verification status, FCM tokens
- **`trips`**: Trip documents with pickup/dropoff, multiple stops array, status (pending/accepted/completed), fare, timestamps
- **`hotspots`**: High-demand areas for displaying on map

### Key Data Flows
1. **Trip Request**: FCM → `_firebaseMessagingBackgroundHandler` → TripProvider.processFcmNotification → TripRequestDialog
2. **Location Updates**: Geolocator stream → LocationProvider → Firestore `drivers/{uid}` every 10 seconds when online
3. **Trip State**: Firestore trip doc snapshot → TripProvider listener → Auto-navigate to TripTrackerScreen
4. **Persistent State**: SharedPreferences stores active trip IDs, stop progress, and pending FCM payloads for cold starts

## Feature Flags
```dart
// lib/main.dart
const bool ENABLE_FACE_VERIFICATION = false;  // Daily face verification requirement

// lib/screens/auth_wrapper.dart
const bool ENABLE_FACE_VERIFICATION = false;  // Duplicate for screen-level control
```
Toggle to `true` to enforce daily face verification via Google ML Kit before going online.

## Critical Workflows

### Running the App
```powershell
flutter pub get
flutter run
```
Android requires `google-services.json` in `android/app/`. Firebase initialization happens in [lib/main.dart](lib/main.dart) `main()`.

### Testing
No automated tests currently (widget_test.dart is boilerplate). Manual testing focuses on:
- FCM notifications in background/foreground/killed states
- Multi-stop trip navigation sequence
- Location permission edge cases (denied/denied forever)

### Building for Production
```powershell
flutter build apk --release
flutter build appbundle --release
```

## Code Conventions

### Navigation
- Global `navigatorKey` in [lib/main.dart](lib/main.dart) enables navigation from FCM background handlers
- Route-based navigation not used; direct `Navigator.push/pushReplacement` with context
- Example: Automatic navigation to `TripTrackerScreen` when trip status becomes 'accepted'

### Firestore Updates
Always update both local provider state AND Firestore document:
```dart
// CORRECT pattern from TripProvider.acceptTrip()
await _firestore.collection('trips').doc(tripId).update({'status': 'accepted'});
_currentTripId = tripId;
notifyListeners();
```

### Multi-Stop Trip Handling
Trips use `stops` array field. [lib/screens/trip_tracker_screen.dart](lib/screens/trip_tracker_screen.dart) tracks current stop index via SharedPreferences:
```dart
await prefs.setInt('stop_index_${tripId}', currentStopIndex);
```
Completion logic: Mark stop complete → Update Firestore → Load next stop → Show "Complete Trip" when all stops done.

### Error Handling Pattern
Print statements for debugging (no formal logging framework):
```dart
try {
  // Firebase operation
} catch (e) {
  print('Error description: $e');
  return defaultValue; // or show SnackBar
}
```

### Google Maps Integration
- Uses `google_maps_flutter` package
- Polylines via `flutter_polyline_points` with Google Directions API
- API key required in `AndroidManifest.xml` and `AppDelegate.swift`
- Map controller stored in LocationProvider to programmatically animate camera

## Firebase Configuration

### Cloud Messaging Setup
1. FCM tokens updated in `drivers/{uid}/fcmToken` field
2. Background handler: `_firebaseMessagingBackgroundHandler` in [lib/main.dart](lib/main.dart)
3. Notification payload must include `notificationType: 'tripRequest'` or `'tripUpdate'`
4. Cold-start requests stored in SharedPreferences key `'pendingTripRequest'`

### Cloud Functions (Optional)
HotspotService calls Cloud Function `getHotspots`, falls back to direct Firestore query if unavailable:
```dart
// lib/services/hotspot_service.dart
HttpsCallable callable = _functions.httpsCallable('getHotspots');
// Fallback: getHotspotsFromFirestore()
```

## Common Pitfalls
- **Don't** call `notifyListeners()` before async Firestore operations complete
- **Always** check `mounted` before showing dialogs in async callbacks
- **Remember** SharedPreferences for persisting trip state across app kills
- **Location permissions** must be granted at runtime; handle `deniedForever` case by directing to settings
- **Face verification images** stored in Firebase Storage at `face_verification/{uid}/reference.jpg`

## File Structure Patterns
- **screens/**: Full-page widgets with Scaffold
- **widgets/**: Reusable components (DriverMap, OnlineToggle, TripRequestDialog)
- **services/**: Non-UI logic (FaceVerificationService, DirectionsService, HotspotService)
- **models/**: Data classes (currently only EarningsSummary)

## External Dependencies
- Firebase (auth, firestore, messaging, storage, functions)
- Google Maps Platform (Maps SDK, Directions API, Geocoding API)
- Google ML Kit (face detection for verification feature)
- Geolocator (GPS tracking)

When modifying provider state, always consider both in-memory state and Firestore persistence. Most screens listen to provider changes via `Consumer<T>` or `context.watch<T>()`.
