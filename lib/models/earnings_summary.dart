  // Model class to store earnings summary
  import 'package:cloud_firestore/cloud_firestore.dart';

class EarningsSummary {
    final double totalEarnings;
    final int tripCount;
    final List<QueryDocumentSnapshot> trips;
    
    EarningsSummary({
      required this.totalEarnings, 
      required this.tripCount,
      required this.trips
    });
  }