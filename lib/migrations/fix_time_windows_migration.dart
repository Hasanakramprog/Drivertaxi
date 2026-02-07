import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_driver_app/models/driver.dart';
import 'package:taxi_driver_app/models/driver_tier.dart';

/// Migration script to fix time window timestamps for existing drivers
///
/// PROBLEM: Existing drivers have old windowStart timestamps that cause
/// windows to reset on every trip request.
///
/// SOLUTION: Update all drivers' time windows to have current timestamps
/// while preserving their existing trip counts.

class MetricsMigration {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fix a single driver's metrics
  Future<void> fixDriverMetrics(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) {
        print('❌ Driver $driverId not found');
        return;
      }

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics;

      if (currentMetrics == null) {
        print('⚠️  Driver $driverId has no metrics, skipping');
        return;
      }

      final now = DateTime.now();

      // Check if windows need fixing
      final last24hAge = now.difference(currentMetrics.last24h.windowStart);
      final last7dAge = now.difference(currentMetrics.last7days.windowStart);
      final last30dAge = now.difference(currentMetrics.last30days.windowStart);

      print('📊 Driver: $driverId');
      print('   24h window age: ${last24hAge.inHours} hours');
      print('   7d window age: ${last7dAge.inDays} days');
      print('   30d window age: ${last30dAge.inDays} days');

      // Create new windows with CURRENT timestamps but PRESERVE existing counts
      final fixed24h = AcceptanceWindow(
        accepted: currentMetrics.last24h.accepted,
        rejected: currentMetrics.last24h.rejected,
        cancelled: currentMetrics.last24h.cancelled,
        total: currentMetrics.last24h.total,
        rate: currentMetrics.last24h.rate,
        windowStart: now.subtract(
          Duration(hours: 1),
        ), // Set to 1 hour ago (fresh but not expired)
      );

      final fixed7days = AcceptanceWindow(
        accepted: currentMetrics.last7days.accepted,
        rejected: currentMetrics.last7days.rejected,
        cancelled: currentMetrics.last7days.cancelled,
        total: currentMetrics.last7days.total,
        rate: currentMetrics.last7days.rate,
        windowStart: now.subtract(
          Duration(days: 1),
        ), // Set to 1 day ago (fresh but not expired)
      );

      final fixed30days = AcceptanceWindow(
        accepted: currentMetrics.last30days.accepted,
        rejected: currentMetrics.last30days.rejected,
        cancelled: currentMetrics.last30days.cancelled,
        total: currentMetrics.last30days.total,
        rate: currentMetrics.last30days.rate,
        windowStart: now.subtract(
          Duration(days: 5),
        ), // Set to 5 days ago (fresh but not expired)
      );

      // Update metrics with fixed windows
      final fixedMetrics = currentMetrics.copyWith(
        last24h: fixed24h,
        last7days: fixed7days,
        last30days: fixed30days,
        lastUpdated: now,
      );

      // Save to Firestore
      await driverRef.update({'metrics': fixedMetrics.toMap()});

      print('✅ Fixed metrics for driver $driverId');
      print('   New 24h window start: ${fixed24h.windowStart}');
      print('   New 7d window start: ${fixed7days.windowStart}');
      print('   New 30d window start: ${fixed30days.windowStart}');
      print('');
    } catch (e) {
      print('❌ Error fixing driver $driverId: $e');
    }
  }

  /// Fix all drivers in the system
  Future<void> fixAllDrivers() async {
    try {
      print('🔧 Starting metrics migration for all drivers...');
      print('=' * 60);

      final driversSnapshot = await _firestore.collection('drivers').get();
      int fixed = 0;
      int skipped = 0;
      int errors = 0;

      for (final doc in driversSnapshot.docs) {
        try {
          await fixDriverMetrics(doc.id);
          fixed++;
        } catch (e) {
          print('❌ Error with driver ${doc.id}: $e');
          errors++;
        }
      }

      print('=' * 60);
      print('✅ Migration complete!');
      print('   Fixed: $fixed drivers');
      print('   Skipped: $skipped drivers');
      print('   Errors: $errors drivers');
      print('   Total: ${driversSnapshot.docs.length} drivers');
    } catch (e) {
      print('❌ Migration failed: $e');
    }
  }

  /// Check if a driver needs migration (for testing)
  Future<bool> needsMigration(String driverId) async {
    try {
      final driverDoc =
          await _firestore.collection('drivers').doc(driverId).get();
      if (!driverDoc.exists) return false;

      final driver = Driver.fromFirestore(driverDoc);
      if (driver.metrics == null) return false;

      final now = DateTime.now();
      final last24hAge = now.difference(driver.metrics!.last24h.windowStart);
      final last7dAge = now.difference(driver.metrics!.last7days.windowStart);
      final last30dAge = now.difference(driver.metrics!.last30days.windowStart);

      // If any window is older than its duration, it needs migration
      return last24hAge > Duration(hours: 24) ||
          last7dAge > Duration(days: 7) ||
          last30dAge > Duration(days: 30);
    } catch (e) {
      print('Error checking driver $driverId: $e');
      return false;
    }
  }
}

// ============================================================================
// USAGE INSTRUCTIONS
// ============================================================================

/*

1. To fix a single driver:
   
   final migration = MetricsMigration();
   await migration.fixDriverMetrics('driver-id-here');


2. To fix all drivers:
   
   final migration = MetricsMigration();
   await migration.fixAllDrivers();


3. To check if a driver needs migration:
   
   final migration = MetricsMigration();
   final needs = await migration.needsMigration('driver-id-here');
   print('Needs migration: $needs');


4. Run this from your app (e.g., in a button press or admin screen):
   
   ElevatedButton(
     onPressed: () async {
       final migration = MetricsMigration();
       await migration.fixAllDrivers();
     },
     child: Text('Fix All Driver Metrics'),
   )

*/
