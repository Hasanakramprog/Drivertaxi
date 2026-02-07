// Debug script to check driver metrics in Firestore
// Run this to see what's actually stored

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_driver_app/models/driver.dart';

Future<void> debugDriverMetrics(String driverId) async {
  final firestore = FirebaseFirestore.instance;
  final driverDoc = await firestore.collection('drivers').doc(driverId).get();

  if (!driverDoc.exists) {
    print('❌ Driver not found');
    return;
  }

  final driver = Driver.fromFirestore(driverDoc);
  final metrics = driver.metrics;

  if (metrics == null) {
    print('❌ No metrics found for driver');
    return;
  }

  print('📊 Driver Metrics Debug Info');
  print('=' * 50);
  print('Driver ID: $driverId');
  print('Current Time: ${DateTime.now()}');
  print('');

  print('📈 Global Counters:');
  print('  Trips Requested: ${metrics.tripsRequested}');
  print('  Trips Accepted: ${metrics.tripsAccepted}');
  print('  Trips Cancelled: ${metrics.tripsCancelled}');
  print('  Trips Completed: ${metrics.tripsCompleted}');
  print('');

  print('⏰ Last 24 Hours Window:');
  print('  Window Start: ${metrics.last24h.windowStart}');
  print(
    '  Age: ${DateTime.now().difference(metrics.last24h.windowStart).inHours} hours',
  );
  print(
    '  Should Reset? ${DateTime.now().difference(metrics.last24h.windowStart) > Duration(hours: 24)}',
  );
  print('  Accepted: ${metrics.last24h.accepted}');
  print('  Rejected: ${metrics.last24h.rejected}');
  print('  Cancelled: ${metrics.last24h.cancelled}');
  print('  Total: ${metrics.last24h.total}');
  print('  Rate: ${metrics.last24h.rate}%');
  print('');

  print('📅 Last 7 Days Window:');
  print('  Window Start: ${metrics.last7days.windowStart}');
  print(
    '  Age: ${DateTime.now().difference(metrics.last7days.windowStart).inDays} days',
  );
  print(
    '  Should Reset? ${DateTime.now().difference(metrics.last7days.windowStart) > Duration(days: 7)}',
  );
  print('  Accepted: ${metrics.last7days.accepted}');
  print('  Rejected: ${metrics.last7days.rejected}');
  print('  Cancelled: ${metrics.last7days.cancelled}');
  print('  Total: ${metrics.last7days.total}');
  print('  Rate: ${metrics.last7days.rate}%');
  print('');

  print('📆 Last 30 Days Window:');
  print('  Window Start: ${metrics.last30days.windowStart}');
  print(
    '  Age: ${DateTime.now().difference(metrics.last30days.windowStart).inDays} days',
  );
  print(
    '  Should Reset? ${DateTime.now().difference(metrics.last30days.windowStart) > Duration(days: 30)}',
  );
  print('  Accepted: ${metrics.last30days.accepted}');
  print('  Rejected: ${metrics.last30days.rejected}');
  print('  Cancelled: ${metrics.last30days.cancelled}');
  print('  Total: ${metrics.last30days.total}');
  print('  Rate: ${metrics.last30days.rate}%');
  print('');

  print('🎯 Calculated Metrics:');
  print('  Acceptance Rate: ${metrics.acceptanceRate}%');
  print('  Cancellation Rate: ${metrics.cancellationRate}%');
  print('  Reliability Score: ${metrics.reliabilityScore}');
  print('  Tier: ${metrics.tier.displayName}');
  print('  In Grace Period: ${metrics.isInGracePeriod}');
  print('  Last Updated: ${metrics.lastUpdated}');
  print('=' * 50);
}

// Usage:
// Call this function with your driver ID to see what's stored
// debugDriverMetrics('your-driver-id-here');
