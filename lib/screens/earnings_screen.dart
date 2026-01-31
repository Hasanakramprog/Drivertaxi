// TODO Implement this library.// lib/screens/earnings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taxi_driver_app/models/earnings_summary.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({Key? key}) : super(key: key);

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Date formatters
  final DateFormat _dateFormat = DateFormat('MMM d');
  final DateFormat _timeFormat = DateFormat('h:mm a');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
  );

  // Cached earnings data
  Map<String, EarningsSummary> _earningsCache = {};

  // Loading states
  bool _loadingToday = true;
  bool _loadingWeek = true;
  bool _loadingMonth = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Load data for each period
    _loadEarnings('today');
    _loadEarnings('week');
    _loadEarnings('month');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Load earnings data for a specific period
  Future<void> _loadEarnings(String period) async {
    if (_auth.currentUser == null) return;

    setState(() {
      switch (period) {
        case 'today':
          _loadingToday = true;
          break;
        case 'week':
          _loadingWeek = true;
          break;
        case 'month':
          _loadingMonth = true;
          break;
      }
    });

    try {
      DateTime startDate = _getPeriodStartDate(period);
      final startTimestamp = Timestamp.fromDate(startDate);

      // Query Firestore for completed trips in the period
      final querySnapshot =
          await _firestore
              .collection('trips')
              .where('driverId', isEqualTo: _auth.currentUser!.uid)
              .where('status', isEqualTo: 'completed')
              .where('completionTime', isGreaterThanOrEqualTo: startTimestamp)
              .orderBy('completionTime', descending: true)
              .get();

      // Calculate total earnings
      double totalEarnings = 0;
      for (var doc in querySnapshot.docs) {
        final trip = doc.data();
        final fare = trip['fare'];
        if (fare != null) {
          if (fare is num) {
            totalEarnings += fare.toDouble();
          } else if (fare is String) {
            totalEarnings += double.tryParse(fare) ?? 0;
          }
        }
      }

      // Store in cache
      _earningsCache[period] = EarningsSummary(
        totalEarnings: totalEarnings,
        tripCount: querySnapshot.docs.length,
        trips: querySnapshot.docs,
      );
    } catch (e) {
      print('Error loading $period earnings: $e');
    } finally {
      // Update loading state
      setState(() {
        switch (period) {
          case 'today':
            _loadingToday = false;
            break;
          case 'week':
            _loadingWeek = false;
            break;
          case 'month':
            _loadingMonth = false;
            break;
        }
      });
    }
  }

  // Helper to get the start date for a period
  DateTime _getPeriodStartDate(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case 'today':
        return today;
      case 'week':
        // Go back to the start of the week (assuming Sunday is first day)
        return today.subtract(Duration(days: today.weekday % 7));
      case 'month':
        return DateTime(now.year, now.month, 1);
      default:
        return today;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'This Week'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEarningsTab('today', _loadingToday),
          _buildEarningsTab('week', _loadingWeek),
          _buildEarningsTab('month', _loadingMonth),
        ],
      ),
    );
  }

  Widget _buildEarningsTab(String period, bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get earnings data from cache
    final earnings = _earningsCache[period];

    if (earnings == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber),
            const SizedBox(height: 16),
            Text('Could not load earnings data'),
            ElevatedButton(
              onPressed: () => _loadEarnings(period),
              child: Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadEarnings(period),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEarningsSummary(
              earnings.totalEarnings,
              earnings.tripCount,
              period,
            ),
            _buildTripList(earnings.trips),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsSummary(
    double totalEarnings,
    int tripCount,
    String periodName,
  ) {
    String periodLabel;
    switch (periodName) {
      case 'today':
        periodLabel = 'Today\'s Earnings';
        break;
      case 'week':
        periodLabel = 'This Week\'s Earnings';
        break;
      case 'month':
        periodLabel = 'This Month\'s Earnings';
        break;
      default:
        periodLabel = 'Earnings';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currencyFormat.format(totalEarnings),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Completed Trips',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tripCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (tripCount > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Average Per Trip',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currencyFormat.format(totalEarnings / tripCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripList(List<QueryDocumentSnapshot> trips) {
    if (trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No trips completed in this period',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Trip History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: trips.length,
          itemBuilder: (context, index) {
            final trip = trips[index].data() as Map<String, dynamic>;

            // Safely parse timestamps with null check
            final Timestamp? completionTimestamp =
                trip['completionTime'] as Timestamp?;
            final DateTime completionTime =
                completionTimestamp?.toDate() ?? DateTime.now();

            // Get pickup and dropoff from nested objects
            final pickup = trip['pickup'] as Map<String, dynamic>? ?? {};
            final dropoff = trip['dropoff'] as Map<String, dynamic>? ?? {};

            // Get fare
            final dynamic fareValue = trip['fare'];
            double fare = 0.0;
            if (fareValue is num) {
              fare = fareValue.toDouble();
            } else if (fareValue is String) {
              fare = double.tryParse(fareValue) ?? 0.0;
            }

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: ListTile(
                title: Text(
                  '${pickup['address'] ?? 'Unknown'} to ${dropoff['address'] ?? 'Unknown'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_dateFormat.format(completionTime)}, ${_timeFormat.format(completionTime)}',
                ),
                trailing: Text(
                  _currencyFormat.format(fare),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  // Optional: Navigate to trip details
                  // Navigator.of(context).push(
                  //   MaterialPageRoute(
                  //     builder: (context) => TripDetailsScreen(tripId: trips[index].id),
                  //   ),
                  // );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
