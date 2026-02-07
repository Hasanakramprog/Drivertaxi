import 'package:cloud_firestore/cloud_firestore.dart';

/// Driver tier levels based on performance metrics
enum DriverTier {
  platinum,
  gold,
  silver,
  bronze;

  /// Display name for the tier
  String get displayName {
    switch (this) {
      case DriverTier.platinum:
        return 'Platinum';
      case DriverTier.gold:
        return 'Gold';
      case DriverTier.silver:
        return 'Silver';
      case DriverTier.bronze:
        return 'Bronze';
    }
  }

  /// Icon emoji for the tier
  String get icon {
    switch (this) {
      case DriverTier.platinum:
        return '🏆';
      case DriverTier.gold:
        return '🥇';
      case DriverTier.silver:
        return '🥈';
      case DriverTier.bronze:
        return '🥉';
    }
  }

  /// Color code for the tier (hex string)
  String get colorHex {
    switch (this) {
      case DriverTier.platinum:
        return '#E5E4E2'; // Platinum
      case DriverTier.gold:
        return '#FFD700'; // Gold
      case DriverTier.silver:
        return '#C0C0C0'; // Silver
      case DriverTier.bronze:
        return '#CD7F32'; // Bronze
    }
  }

  /// Priority bonus points for driver selection
  double get priorityBonus {
    switch (this) {
      case DriverTier.platinum:
        return 15.0;
      case DriverTier.gold:
        return 10.0;
      case DriverTier.silver:
        return 5.0;
      case DriverTier.bronze:
        return 0.0;
    }
  }

  /// Earnings bonus multiplier
  double get bonusMultiplier {
    switch (this) {
      case DriverTier.platinum:
        return 1.2; // 20% bonus
      case DriverTier.gold:
        return 1.1; // 10% bonus
      case DriverTier.silver:
        return 1.0; // No bonus
      case DriverTier.bronze:
        return 1.0; // No bonus
    }
  }

  /// Minimum acceptance rate required for this tier
  double get minAcceptanceRate {
    switch (this) {
      case DriverTier.platinum:
        return 95.0;
      case DriverTier.gold:
        return 85.0;
      case DriverTier.silver:
        return 75.0;
      case DriverTier.bronze:
        return 0.0;
    }
  }

  /// Minimum user rating required for this tier
  double get minUserRating {
    switch (this) {
      case DriverTier.platinum:
        return 4.8;
      case DriverTier.gold:
        return 4.5;
      case DriverTier.silver:
        return 4.0;
      case DriverTier.bronze:
        return 0.0;
    }
  }

  /// Description of tier benefits
  String get benefits {
    switch (this) {
      case DriverTier.platinum:
        return 'First priority for trips • 20% earnings bonus • Premium support';
      case DriverTier.gold:
        return 'High priority for trips • 10% earnings bonus • Priority support';
      case DriverTier.silver:
        return 'Standard priority • Standard support';
      case DriverTier.bronze:
        return 'Lower priority • Account under review';
    }
  }

  /// Convert from string
  static DriverTier fromString(String value) {
    switch (value.toLowerCase()) {
      case 'platinum':
        return DriverTier.platinum;
      case 'gold':
        return DriverTier.gold;
      case 'silver':
        return DriverTier.silver;
      case 'bronze':
        return DriverTier.bronze;
      default:
        return DriverTier.silver; // Default tier
    }
  }

  /// Convert to string for Firestore
  String toFirestore() {
    return name;
  }
}

/// Tracks acceptance metrics over a specific time window
class AcceptanceWindow {
  final int accepted;
  final int rejected;
  final int cancelled;
  final int total;
  final double rate;
  final DateTime windowStart;

  AcceptanceWindow({
    required this.accepted,
    required this.rejected,
    required this.cancelled,
    required this.total,
    required this.rate,
    required this.windowStart,
  });

  factory AcceptanceWindow.empty(DateTime windowStart) {
    return AcceptanceWindow(
      accepted: 0,
      rejected: 0,
      cancelled: 0,
      total: 0,
      rate: 0.0,
      windowStart: windowStart,
    );
  }

  factory AcceptanceWindow.fromMap(Map<String, dynamic> map) {
    return AcceptanceWindow(
      accepted: map['accepted'] ?? 0,
      rejected: map['rejected'] ?? 0,
      cancelled: map['cancelled'] ?? 0,
      total: map['total'] ?? 0,
      rate: (map['rate'] ?? 0.0).toDouble(),
      windowStart:
          map['windowStart'] is Timestamp
              ? (map['windowStart'] as Timestamp).toDate()
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'accepted': accepted,
      'rejected': rejected,
      'cancelled': cancelled,
      'total': total,
      'rate': rate,
      'windowStart': Timestamp.fromDate(windowStart),
    };
  }

  /// Calculate acceptance rate
  static double calculateRate(int accepted, int total) {
    if (total == 0) return 0.0;
    return (accepted / total) * 100.0;
  }

  /// Create updated window with new trip data
  AcceptanceWindow copyWithUpdate({
    int? acceptedDelta,
    int? rejectedDelta,
    int? cancelledDelta,
    int? requestedDelta, // FIX: Add for API consistency
  }) {
    final newAccepted = accepted + (acceptedDelta ?? 0);
    final newRejected = rejected + (rejectedDelta ?? 0);
    final newCancelled = cancelled + (cancelledDelta ?? 0);
    final newTotal = newAccepted + newRejected + newCancelled;
    final newRate = calculateRate(newAccepted, newTotal);

    return AcceptanceWindow(
      accepted: newAccepted,
      rejected: newRejected,
      cancelled: newCancelled,
      total: newTotal,
      rate: newRate,
      windowStart: windowStart,
    );
  }
}

/// Comprehensive driver performance metrics
class DriverMetrics {
  // Trip counters
  final int tripsCompleted;
  final int tripsAccepted;
  final int tripsCancelled;
  final int tripsRequested;

  // Calculated rates
  final double acceptanceRate;
  final double cancellationRate;
  final double reliabilityScore;

  // Tier information
  final DriverTier tier;

  // Time-windowed metrics
  final AcceptanceWindow last24h;
  final AcceptanceWindow last7days;
  final AcceptanceWindow last30days;

  // Metadata
  final DateTime lastUpdated;
  final bool isInGracePeriod;

  DriverMetrics({
    this.tripsCompleted = 0,
    this.tripsAccepted = 0,
    this.tripsCancelled = 0,
    this.tripsRequested = 0,
    this.acceptanceRate = 0.0,
    this.cancellationRate = 0.0,
    this.reliabilityScore = 0.0,
    this.tier = DriverTier.silver,
    AcceptanceWindow? last24h,
    AcceptanceWindow? last7days,
    AcceptanceWindow? last30days,
    DateTime? lastUpdated,
    this.isInGracePeriod = true,
  }) : last24h = last24h ?? AcceptanceWindow.empty(DateTime.now()),
       last7days = last7days ?? AcceptanceWindow.empty(DateTime.now()),
       last30days = last30days ?? AcceptanceWindow.empty(DateTime.now()),
       lastUpdated = lastUpdated ?? DateTime.now();

  factory DriverMetrics.fromMap(Map<String, dynamic> map) {
    return DriverMetrics(
      tripsCompleted: map['tripsCompleted'] ?? 0,
      tripsAccepted: map['tripsAccepted'] ?? 0,
      tripsCancelled: map['tripsCancelled'] ?? 0,
      tripsRequested: map['tripsRequested'] ?? 0,
      acceptanceRate: (map['acceptanceRate'] ?? 0.0).toDouble(),
      cancellationRate: (map['cancellationRate'] ?? 0.0).toDouble(),
      reliabilityScore: (map['reliabilityScore'] ?? 0.0).toDouble(),
      tier: DriverTier.fromString(map['tier'] ?? 'silver'),
      last24h:
          map['last24h'] != null
              ? AcceptanceWindow.fromMap(map['last24h'])
              : null,
      last7days:
          map['last7days'] != null
              ? AcceptanceWindow.fromMap(map['last7days'])
              : null,
      last30days:
          map['last30days'] != null
              ? AcceptanceWindow.fromMap(map['last30days'])
              : null,
      lastUpdated:
          map['lastUpdated'] is Timestamp
              ? (map['lastUpdated'] as Timestamp).toDate()
              : DateTime.now(),
      isInGracePeriod: map['isInGracePeriod'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tripsCompleted': tripsCompleted,
      'tripsAccepted': tripsAccepted,
      'tripsCancelled': tripsCancelled,
      'tripsRequested': tripsRequested,
      'acceptanceRate': acceptanceRate,
      'cancellationRate': cancellationRate,
      'reliabilityScore': reliabilityScore,
      'tier': tier.toFirestore(),
      'last24h': last24h.toMap(),
      'last7days': last7days.toMap(),
      'last30days': last30days.toMap(),
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'isInGracePeriod': isInGracePeriod,
    };
  }

  /// Check if grace period is over (20 completed trips)
  bool get shouldExitGracePeriod => tripsCompleted >= 20;

  /// Get formatted acceptance rate string
  String get formattedAcceptanceRate => '${acceptanceRate.toStringAsFixed(1)}%';

  /// Get formatted cancellation rate string
  String get formattedCancellationRate =>
      '${cancellationRate.toStringAsFixed(1)}%';

  /// Get formatted reliability score string
  String get formattedReliabilityScore => reliabilityScore.toStringAsFixed(1);

  /// Check if driver is at risk of tier downgrade
  bool get isAtRisk {
    if (tier == DriverTier.bronze) return false;

    final nextLowerTier = _getNextLowerTier();
    return acceptanceRate < tier.minAcceptanceRate + 5.0 ||
        reliabilityScore < nextLowerTier.minUserRating + 0.2;
  }

  /// Get the next lower tier
  DriverTier _getNextLowerTier() {
    switch (tier) {
      case DriverTier.platinum:
        return DriverTier.gold;
      case DriverTier.gold:
        return DriverTier.silver;
      case DriverTier.silver:
        return DriverTier.bronze;
      case DriverTier.bronze:
        return DriverTier.bronze;
    }
  }

  /// Get message for next tier requirements
  String getNextTierRequirements(double currentUserRating) {
    final nextTier = _getNextHigherTier();
    if (nextTier == tier) {
      return 'You are at the highest tier!';
    }

    final acceptanceGap = nextTier.minAcceptanceRate - acceptanceRate;
    final ratingGap = nextTier.minUserRating - currentUserRating;

    final requirements = <String>[];
    if (acceptanceGap > 0) {
      requirements.add(
        'Increase acceptance rate by ${acceptanceGap.toStringAsFixed(1)}%',
      );
    }
    if (ratingGap > 0) {
      requirements.add(
        'Improve rating by ${ratingGap.toStringAsFixed(1)} stars',
      );
    }

    if (requirements.isEmpty) {
      return 'Keep up the great work to reach ${nextTier.displayName}!';
    }

    return 'To reach ${nextTier.displayName}: ${requirements.join(', ')}';
  }

  /// Get the next higher tier
  DriverTier _getNextHigherTier() {
    switch (tier) {
      case DriverTier.bronze:
        return DriverTier.silver;
      case DriverTier.silver:
        return DriverTier.gold;
      case DriverTier.gold:
        return DriverTier.platinum;
      case DriverTier.platinum:
        return DriverTier.platinum;
    }
  }

  DriverMetrics copyWith({
    int? tripsCompleted,
    int? tripsAccepted,
    int? tripsCancelled,
    int? tripsRequested,
    double? acceptanceRate,
    double? cancellationRate,
    double? reliabilityScore,
    DriverTier? tier,
    AcceptanceWindow? last24h,
    AcceptanceWindow? last7days,
    AcceptanceWindow? last30days,
    DateTime? lastUpdated,
    bool? isInGracePeriod,
  }) {
    return DriverMetrics(
      tripsCompleted: tripsCompleted ?? this.tripsCompleted,
      tripsAccepted: tripsAccepted ?? this.tripsAccepted,
      tripsCancelled: tripsCancelled ?? this.tripsCancelled,
      tripsRequested: tripsRequested ?? this.tripsRequested,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      cancellationRate: cancellationRate ?? this.cancellationRate,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      tier: tier ?? this.tier,
      last24h: last24h ?? this.last24h,
      last7days: last7days ?? this.last7days,
      last30days: last30days ?? this.last30days,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isInGracePeriod: isInGracePeriod ?? this.isInGracePeriod,
    );
  }
}
