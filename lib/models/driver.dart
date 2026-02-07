import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_driver_app/models/driver_tier.dart';

class VehicleDetails {
  final String make;
  final String model;
  final int year;
  final String color;
  final String licensePlate;

  VehicleDetails({
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.licensePlate,
  });

  factory VehicleDetails.fromMap(Map<String, dynamic> map) {
    // Handle year as either String or int
    int year = 0;
    if (map['year'] != null) {
      if (map['year'] is int) {
        year = map['year'];
      } else if (map['year'] is String) {
        year = int.tryParse(map['year']) ?? 0;
      }
    }

    return VehicleDetails(
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      year: year,
      color: map['color'] ?? '',
      licensePlate: map['licensePlate'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'make': make,
      'model': model,
      'year': year,
      'color': color,
      'licensePlate': licensePlate,
    };
  }

  VehicleDetails copyWith({
    String? make,
    String? model,
    int? year,
    String? color,
    String? licensePlate,
  }) {
    return VehicleDetails(
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      licensePlate: licensePlate ?? this.licensePlate,
    );
  }
}

class Driver {
  final String id;
  final String displayName;
  final String email;
  final String phoneNumber;
  final String? baseFaceImageUrl;
  final bool isApproved;
  final bool isOnline;
  final double rating;
  final int ratingCount;
  final VehicleDetails vehicleDetails;
  final DriverMetrics? metrics;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Driver({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phoneNumber,
    this.baseFaceImageUrl,
    this.isApproved = false,
    this.isOnline = false,
    this.rating = 5.0,
    this.ratingCount = 0,
    required this.vehicleDetails,
    this.metrics,
    this.createdAt,
    this.updatedAt,
  });

  factory Driver.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Driver.fromMap(data, doc.id);
  }

  factory Driver.fromMap(Map<String, dynamic> map, String id) {
    // Safe conversion for rating
    double rating = 5.0;
    if (map['rating'] != null) {
      if (map['rating'] is double) {
        rating = map['rating'];
      } else if (map['rating'] is int) {
        rating = (map['rating'] as int).toDouble();
      } else if (map['rating'] is String) {
        rating = double.tryParse(map['rating']) ?? 5.0;
      } else if (map['rating'] is num) {
        rating = (map['rating'] as num).toDouble();
      }
    }

    // Safe conversion for ratingCount
    int ratingCount = 0;
    if (map['ratingCount'] != null) {
      if (map['ratingCount'] is int) {
        ratingCount = map['ratingCount'];
      } else if (map['ratingCount'] is String) {
        ratingCount = int.tryParse(map['ratingCount']) ?? 0;
      } else if (map['ratingCount'] is num) {
        ratingCount = (map['ratingCount'] as num).toInt();
      }
    }

    return Driver(
      id: id,
      displayName: map['displayName'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      baseFaceImageUrl: map['baseFaceImageUrl'],
      isApproved: map['isApproved'] ?? false,
      isOnline: map['isOnline'] ?? false,
      rating: rating,
      ratingCount: ratingCount,
      vehicleDetails: VehicleDetails.fromMap(map['vehicleDetails'] ?? {}),
      metrics:
          map['metrics'] != null ? DriverMetrics.fromMap(map['metrics']) : null,
      createdAt:
          map['createdAt'] is Timestamp
              ? (map['createdAt'] as Timestamp).toDate()
              : null,
      updatedAt:
          map['updatedAt'] is Timestamp
              ? (map['updatedAt'] as Timestamp).toDate()
              : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'phoneNumber': phoneNumber,
      'baseFaceImageUrl': baseFaceImageUrl,
      'isApproved': isApproved,
      'isOnline': isOnline,
      'rating': rating,
      'ratingCount': ratingCount,
      'vehicleDetails': vehicleDetails.toMap(),
      'metrics': metrics?.toMap(),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  Driver copyWith({
    String? id,
    String? displayName,
    String? email,
    String? phoneNumber,
    String? baseFaceImageUrl,
    bool? isApproved,
    bool? isOnline,
    double? rating,
    int? ratingCount,
    VehicleDetails? vehicleDetails,
    DriverMetrics? metrics,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Driver(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      baseFaceImageUrl: baseFaceImageUrl ?? this.baseFaceImageUrl,
      isApproved: isApproved ?? this.isApproved,
      isOnline: isOnline ?? this.isOnline,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      vehicleDetails: vehicleDetails ?? this.vehicleDetails,
      metrics: metrics ?? this.metrics,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get formattedRating => rating.toStringAsFixed(1);

  String get memberSince {
    if (createdAt == null) return 'N/A';
    return '${createdAt!.month}/${createdAt!.year}';
  }

  bool get hasProfileImage =>
      baseFaceImageUrl != null && baseFaceImageUrl!.isNotEmpty;

  /// Get driver tier (defaults to Silver if no metrics)
  DriverTier get tier => metrics?.tier ?? DriverTier.silver;

  /// Get tier display name
  String get tierDisplayName => tier.displayName;

  /// Get tier icon
  String get tierIcon => tier.icon;

  /// Get acceptance rate
  double get acceptanceRate => metrics?.acceptanceRate ?? 0.0;

  /// Get reliability score
  double get reliabilityScore => metrics?.reliabilityScore ?? 0.0;

  /// Calculate driver selection priority
  /// Higher score = higher priority for trip assignment
  double calculateSelectionPriority(double distanceKm) {
    double priority = reliabilityScore;

    // Add tier bonus
    priority += tier.priorityBonus;

    // Subtract distance penalty (2 points per km)
    priority -= (distanceKm * 2.0);

    return priority;
  }

  /// Check if driver is in grace period
  bool get isInGracePeriod => metrics?.isInGracePeriod ?? true;

  /// Check if driver is at risk of tier downgrade
  bool get isAtRisk => metrics?.isAtRisk ?? false;
}
