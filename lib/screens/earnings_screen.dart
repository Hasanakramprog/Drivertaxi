// TODO Implement this library.// lib/screens/earnings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({Key? key}) : super(key: key);

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  
  // Date formatters
  final DateFormat _dateFormat = DateFormat('MMM d');
  final DateFormat _timeFormat = DateFormat('h:mm a');
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  
  // Trip summary data
  double _todayEarnings = 0;
  double _weekEarnings = 0;
  double _monthEarnings = 0;
  int _todayTrips = 0;
  int _weekTrips = 0;
  int _monthTrips = 0;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEarningsSummary();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadEarningsSummary() async {
    if (_auth.currentUser == null) return;
    
    try {
      final driverId = _auth.currentUser!.uid;
      
      // Get current date info
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);
      
      // Convert to Firestore timestamps
      final todayTimestamp = Timestamp.fromDate(today);
      final weekStartTimestamp = Timestamp.fromDate(weekStart);
      final monthStartTimestamp = Timestamp.fromDate(monthStart);
      
      // Get today's trips
      QuerySnapshot todayTrips = await _firestore
          .collection('trips')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .where('completionTime', isGreaterThanOrEqualTo: todayTimestamp)
          .get();
      
      // Get this week's trips
      QuerySnapshot weekTrips = await _firestore
          .collection('trips')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .where('completionTime', isGreaterThanOrEqualTo: weekStartTimestamp)
          .get();
      
      // Get this month's trips
      QuerySnapshot monthTrips = await _firestore
          .collection('trips')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .where('completionTime', isGreaterThanOrEqualTo: monthStartTimestamp)
          .get();
      
      // Calculate earnings
      double todayTotal = 0;
      double weekTotal = 0;
      double monthTotal = 0;
      
      for (var doc in todayTrips.docs) {
        final tripData = doc.data() as Map<String, dynamic>;
        todayTotal += (tripData['fare'] ?? 0).toDouble();
      }
      
      for (var doc in weekTrips.docs) {
        final tripData = doc.data() as Map<String, dynamic>;
        weekTotal += (tripData['fare'] ?? 0).toDouble();
      }
      
      for (var doc in monthTrips.docs) {
        final tripData = doc.data() as Map<String, dynamic>;
        monthTotal += (tripData['fare'] ?? 0).toDouble();
      }
      
      // Update state
      setState(() {
        _todayEarnings = todayTotal;
        _weekEarnings = weekTotal;
        _monthEarnings = monthTotal;
        _todayTrips = todayTrips.docs.length;
        _weekTrips = weekTrips.docs.length;
        _monthTrips = monthTrips.docs.length;
      });
      
    } catch (e) {
      print('Error loading earnings: $e');
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
          _buildEarningsTab(_todayEarnings, _todayTrips, 'today'),
          _buildEarningsTab(_weekEarnings, _weekTrips, 'week'),
          _buildEarningsTab(_monthEarnings, _monthTrips, 'month'),
        ],
      ),
    );
  }
  
  Widget _buildEarningsTab(double earnings, int tripCount, String period) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Earnings summary card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _currencyFormat.format(earnings),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total Earnings',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            Text(
                              tripCount.toString(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Trips',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              tripCount > 0 
                                  ? _currencyFormat.format(earnings / tripCount) 
                                  : '\$0.00',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Average',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Trip list
            _buildTripList(period),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTripList(String period) {
    if (_auth.currentUser == null) {
      return const Center(child: Text('Not logged in'));
    }
    
    // Determine start date based on period
    DateTime startDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (period) {
      case 'today':
        startDate = today;
        break;
      case 'week':
        startDate = today.subtract(Duration(days: today.weekday - 1));
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      default:
        startDate = today;
    }
    
    final startTimestamp = Timestamp.fromDate(startDate);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trip History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 400, // Fixed height for the list
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('trips')
                .where('driverId', isEqualTo: _auth.currentUser!.uid)
                .where('status', isEqualTo: 'completed')
                .where('completionTime', isGreaterThanOrEqualTo: startTimestamp)
                .orderBy('completionTime', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    'No trips found for this period',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }
              
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final trip = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  
                  // Parse timestamps
                  final completionTime = (trip['completionTime'] as Timestamp).toDate();
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                        '${trip['pickup']?['address'] ?? 'Unknown'} to ${trip['dropoff']?['address'] ?? 'Unknown'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_dateFormat.format(completionTime)}, ${_timeFormat.format(completionTime)}',
                      ),
                      trailing: Text(
                        _currencyFormat.format(trip['fare'] ?? 0),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}