import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefs {
  // Keys
  static const String keyFirstLaunch = 'is_first_launch';
  static const String keyCurrentTheme = 'current_theme';
  static const String keyDriverId = 'driver_id';
  static const String keyLanguage = 'app_language';
  static const String keyPushNotifications = 'push_notifications_enabled';
  static const String keyLastLocation = 'last_known_location';
  static const String keyOnlineStatus = 'driver_online_status';

  // Check if this is the first app launch
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    // If the key doesn't exist, it's the first launch
    return prefs.getBool(keyFirstLaunch) ?? true;
  }

  // Set first launch as complete
  Future<void> setFirstLaunchComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFirstLaunch, false);
  }

  // Reset first launch status (for testing/debugging)
  Future<void> resetFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFirstLaunch, true);
  }

  // Driver ID management
  Future<void> saveDriverId(String driverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDriverId, driverId);
  }

  Future<String?> getDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyDriverId);
  }

  Future<void> removeDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyDriverId);
  }

  // Theme management
  Future<void> saveTheme(String themeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCurrentTheme, themeName);
  }

  Future<String> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyCurrentTheme) ?? 'light';
  }

  // Language management
  Future<void> saveLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLanguage, languageCode);
  }

  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLanguage) ?? 'en';
  }

  // Push notification settings
  Future<void> setPushNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyPushNotifications, enabled);
  }

  Future<bool> getPushNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyPushNotifications) ?? true;
  }

  // Last known location
  Future<void> saveLastLocation(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastLocation, '$lat,$lng');
  }

  Future<Map<String, double>?> getLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final locationStr = prefs.getString(keyLastLocation);
    
    if (locationStr == null) return null;
    
    final parts = locationStr.split(',');
    if (parts.length != 2) return null;
    
    try {
      return {
        'latitude': double.parse(parts[0]),
        'longitude': double.parse(parts[1]),
      };
    } catch (e) {
      return null;
    }
  }

  // Driver online status
  Future<void> setDriverOnlineStatus(bool isOnline) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyOnlineStatus, isOnline);
  }

  Future<bool> getDriverOnlineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyOnlineStatus) ?? false;
  }

  // Clear all data (for logout)
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // We don't want to show onboarding again after logout
    await prefs.setBool(keyFirstLaunch, false);
  }
}