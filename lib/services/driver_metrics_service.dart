import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_driver_app/models/driver.dart';
import 'package:taxi_driver_app/models/driver_tier.dart';

/// Service for managing driver metrics and tier calculations
class DriverMetricsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Grace period threshold (number of completed trips)
  static const int gracePeriodThreshold = 20;

  /// Time window durations
  static const Duration window24h = Duration(hours: 24);
  static const Duration window7days = Duration(days: 7);
  static const Duration window30days = Duration(days: 30);

  /// Update metrics when a trip request is sent to driver
  Future<void> onTripRequested(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics ?? _createInitialMetrics();

      // Update counters
      final updatedMetrics = currentMetrics.copyWith(
        tripsRequested: currentMetrics.tripsRequested + 1,
        lastUpdated: DateTime.now(),
      );

      // Update time windows
      final metricsWithWindows = _updateTimeWindows(
        updatedMetrics,
        requestedDelta: 1,
      );

      // Recalculate rates and scores
      final finalMetrics = _recalculateMetrics(
        metricsWithWindows,
        driver.rating,
      );

      // Save to Firestore
      await driverRef.update({'metrics': finalMetrics.toMap()});
    } catch (e) {
      print('Error updating metrics on trip requested: $e');
    }
  }

  /// Update metrics when driver accepts a trip
  Future<void> onTripAccepted(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics ?? _createInitialMetrics();

      // Update counters
      final updatedMetrics = currentMetrics.copyWith(
        tripsAccepted: currentMetrics.tripsAccepted + 1,
        lastUpdated: DateTime.now(),
      );

      // Update time windows
      final metricsWithWindows = _updateTimeWindows(
        updatedMetrics,
        acceptedDelta: 1,
      );

      // Recalculate rates and scores
      final finalMetrics = _recalculateMetrics(
        metricsWithWindows,
        driver.rating,
      );

      // Save to Firestore
      await driverRef.update({'metrics': finalMetrics.toMap()});
    } catch (e) {
      print('Error updating metrics on trip accepted: $e');
    }
  }

  /// Update metrics when driver cancels a trip
  Future<void> onTripCancelled(String driverId, {String? reason}) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics ?? _createInitialMetrics();

      // Check if cancellation should be counted (valid reasons don't count)
      final shouldCount = !_isValidCancellationReason(reason);

      if (shouldCount) {
        // Update counters
        final updatedMetrics = currentMetrics.copyWith(
          tripsCancelled: currentMetrics.tripsCancelled + 1,
          lastUpdated: DateTime.now(),
        );

        // Update time windows
        final metricsWithWindows = _updateTimeWindows(
          updatedMetrics,
          cancelledDelta: 1,
        );

        // Recalculate rates and scores
        final finalMetrics = _recalculateMetrics(
          metricsWithWindows,
          driver.rating,
        );

        // Save to Firestore
        await driverRef.update({'metrics': finalMetrics.toMap()});
      }
    } catch (e) {
      print('Error updating metrics on trip cancelled: $e');
    }
  }

  /// Update metrics when driver completes a trip
  Future<void> onTripCompleted(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics ?? _createInitialMetrics();

      // Update counters
      final updatedMetrics = currentMetrics.copyWith(
        tripsCompleted: currentMetrics.tripsCompleted + 1,
        lastUpdated: DateTime.now(),
      );

      // Check if grace period should end
      final shouldExitGracePeriod =
          updatedMetrics.tripsCompleted >= gracePeriodThreshold;
      final metricsAfterGrace =
          shouldExitGracePeriod
              ? updatedMetrics.copyWith(isInGracePeriod: false)
              : updatedMetrics;

      // Recalculate rates and scores
      final finalMetrics = _recalculateMetrics(
        metricsAfterGrace,
        driver.rating,
      );

      // Save to Firestore
      await driverRef.update({'metrics': finalMetrics.toMap()});
    } catch (e) {
      print('Error updating metrics on trip completed: $e');
    }
  }

  /// Update metrics when driver rejects/ignores a trip request
  Future<void> onTripRejected(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);
      final currentMetrics = driver.metrics ?? _createInitialMetrics();

      // Update time windows (rejection counts in total but not in accepted)
      final metricsWithWindows = _updateTimeWindows(
        currentMetrics,
        rejectedDelta: 1,
      );

      // Recalculate rates and scores
      final finalMetrics = _recalculateMetrics(
        metricsWithWindows,
        driver.rating,
      );

      // Save to Firestore
      await driverRef.update({'metrics': finalMetrics.toMap()});
    } catch (e) {
      print('Error updating metrics on trip rejected: $e');
    }
  }

  /// Create initial metrics for a new driver
  DriverMetrics _createInitialMetrics() {
    final now = DateTime.now();
    return DriverMetrics(
      tripsCompleted: 0,
      tripsAccepted: 0,
      tripsCancelled: 0,
      tripsRequested: 0,
      acceptanceRate: 0.0,
      cancellationRate: 0.0,
      reliabilityScore: 0.0,
      tier: DriverTier.silver, // Default tier for new drivers
      last24h: AcceptanceWindow.empty(now.subtract(window24h)),
      last7days: AcceptanceWindow.empty(now.subtract(window7days)),
      last30days: AcceptanceWindow.empty(now.subtract(window30days)),
      lastUpdated: now,
      isInGracePeriod: true,
    );
  }

  /// Update time windows with new trip data
  DriverMetrics _updateTimeWindows(
    DriverMetrics metrics, {
    int acceptedDelta = 0,
    int rejectedDelta = 0,
    int cancelledDelta = 0,
    int requestedDelta = 0,
  }) {
    final now = DateTime.now();

    // Check if windows need to be reset
    final should24hReset =
        now.difference(metrics.last24h.windowStart) > window24h;
    final should7dReset =
        now.difference(metrics.last7days.windowStart) > window7days;
    final should30dReset =
        now.difference(metrics.last30days.windowStart) > window30days;

    // Update or reset 24h window
    final new24h =
        should24hReset
            ? AcceptanceWindow.empty(now.subtract(window24h)).copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            )
            : metrics.last24h.copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            );

    // Update or reset 7 days window
    final new7days =
        should7dReset
            ? AcceptanceWindow.empty(now.subtract(window7days)).copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            )
            : metrics.last7days.copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            );

    // Update or reset 30 days window
    final new30days =
        should30dReset
            ? AcceptanceWindow.empty(now.subtract(window30days)).copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            )
            : metrics.last30days.copyWithUpdate(
              acceptedDelta: acceptedDelta,
              rejectedDelta: rejectedDelta,
              cancelledDelta: cancelledDelta,
              requestedDelta: requestedDelta, // FIX: Include requestedDelta
            );

    return metrics.copyWith(
      last24h: new24h,
      last7days: new7days,
      last30days: new30days,
    );
  }

  /// Recalculate all metrics (rates, scores, tier)
  DriverMetrics _recalculateMetrics(DriverMetrics metrics, double userRating) {
    // Calculate overall acceptance rate
    final acceptanceRate =
        metrics.tripsRequested > 0
            ? (metrics.tripsAccepted / metrics.tripsRequested) * 100.0
            : 0.0;

    // Calculate cancellation rate
    final cancellationRate =
        metrics.tripsAccepted > 0
            ? (metrics.tripsCancelled / metrics.tripsAccepted) * 100.0
            : 0.0;

    // Calculate weighted acceptance rate from time windows
    final weightedAcceptance = _calculateWeightedAcceptance(
      metrics.last24h,
      metrics.last7days,
      metrics.last30days,
    );

    // Calculate reliability score
    final reliabilityScore = _calculateReliabilityScore(
      userRating,
      weightedAcceptance,
      cancellationRate,
    );

    // Determine tier
    final tier = _determineTier(
      acceptanceRate,
      userRating,
      reliabilityScore,
      metrics.isInGracePeriod,
    );

    return metrics.copyWith(
      acceptanceRate: acceptanceRate,
      cancellationRate: cancellationRate,
      reliabilityScore: reliabilityScore,
      tier: tier,
      lastUpdated: DateTime.now(),
    );
  }

  /// Calculate weighted acceptance rate from time windows
  /// Recent performance is weighted more heavily
  double _calculateWeightedAcceptance(
    AcceptanceWindow last24h,
    AcceptanceWindow last7days,
    AcceptanceWindow last30days,
  ) {
    // Weights: 24h (50%), 7d (30%), 30d (20%)
    final weighted =
        (last24h.rate * 0.5) + (last7days.rate * 0.3) + (last30days.rate * 0.2);

    return weighted;
  }

  /// Calculate reliability score (0-100)
  /// Formula: (userRating/5.0 * 60) + (weightedAcceptance * 0.35) + max(0, 5 - cancellationPenalty)
  double _calculateReliabilityScore(
    double userRating,
    double weightedAcceptance,
    double cancellationRate,
  ) {
    // User rating component (60% weight)
    final ratingComponent = (userRating / 5.0) * 60.0;

    // Acceptance component (35% weight)
    final acceptanceComponent = weightedAcceptance * 0.35;

    // Cancellation penalty (5% weight)
    final cancellationPenalty =
        cancellationRate / 10.0; // 10% cancellation = 1 point penalty
    final cancellationComponent = (5.0 - cancellationPenalty).clamp(0.0, 5.0);

    final score = ratingComponent + acceptanceComponent + cancellationComponent;

    return score.clamp(0.0, 100.0);
  }

  /// Determine driver tier based on metrics
  DriverTier _determineTier(
    double acceptanceRate,
    double userRating,
    double reliabilityScore,
    bool isInGracePeriod,
  ) {
    // During grace period, keep at Silver
    if (isInGracePeriod) {
      return DriverTier.silver;
    }

    // Check for Platinum
    if (acceptanceRate >= DriverTier.platinum.minAcceptanceRate &&
        userRating >= DriverTier.platinum.minUserRating) {
      return DriverTier.platinum;
    }

    // Check for Gold
    if (acceptanceRate >= DriverTier.gold.minAcceptanceRate &&
        userRating >= DriverTier.gold.minUserRating) {
      return DriverTier.gold;
    }

    // Check for Silver
    if (acceptanceRate >= DriverTier.silver.minAcceptanceRate &&
        userRating >= DriverTier.silver.minUserRating) {
      return DriverTier.silver;
    }

    // Default to Bronze
    return DriverTier.bronze;
  }

  /// Check if cancellation reason is valid (doesn't count against driver)
  bool _isValidCancellationReason(String? reason) {
    if (reason == null) return false;

    final validReasons = [
      'emergency',
      'safety_concern',
      'passenger_no_show',
      'vehicle_issue',
    ];

    return validReasons.contains(reason.toLowerCase());
  }

  /// Get driver selection priority for trip matching
  /// Higher score = higher priority
  Future<List<Map<String, dynamic>>> calculateDriverPriorities(
    List<Driver> availableDrivers,
    double passengerLat,
    double passengerLng,
  ) async {
    final priorities = <Map<String, dynamic>>[];

    for (final driver in availableDrivers) {
      // Calculate distance (simplified - you should use actual distance calculation)
      final distanceKm = _calculateDistance(
        passengerLat,
        passengerLng,
        0.0, // driver.currentLat - you need to add this to driver model
        0.0, // driver.currentLng - you need to add this to driver model
      );

      // Calculate priority using driver's method
      final priority = driver.calculateSelectionPriority(distanceKm);

      priorities.add({
        'driver': driver,
        'priority': priority,
        'distance': distanceKm,
      });
    }

    // Sort by priority (highest first)
    priorities.sort(
      (a, b) => (b['priority'] as double).compareTo(a['priority'] as double),
    );

    return priorities;
  }

  /// Simple distance calculation (Haversine formula)
  /// You should replace this with your actual distance calculation
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    // Simplified - return 0 for now
    // Implement proper Haversine formula or use a package
    return 0.0;
  }

  /// Initialize metrics for existing drivers without metrics
  Future<void> initializeMetricsForDriver(String driverId) async {
    try {
      final driverRef = _firestore.collection('drivers').doc(driverId);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) return;

      final driver = Driver.fromFirestore(driverDoc);

      // Only initialize if metrics don't exist
      if (driver.metrics == null) {
        final initialMetrics = _createInitialMetrics();
        await driverRef.update({'metrics': initialMetrics.toMap()});
        print('Initialized metrics for driver: $driverId');
      }
    } catch (e) {
      print('Error initializing metrics for driver: $e');
    }
  }

  /// Batch initialize metrics for all drivers
  Future<void> initializeMetricsForAllDrivers() async {
    try {
      final driversSnapshot = await _firestore.collection('drivers').get();

      for (final doc in driversSnapshot.docs) {
        await initializeMetricsForDriver(doc.id);
      }

      print('Initialized metrics for ${driversSnapshot.docs.length} drivers');
    } catch (e) {
      print('Error batch initializing metrics: $e');
    }
  }
}
