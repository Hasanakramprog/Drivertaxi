// TODO Implement this library.// lib/screens/trip_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Completed'),
            Tab(text: 'In Progress'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTripList('completed'),
          _buildTripList('active'),
          _buildTripList('cancelled'),
        ],
      ),
    );
  }
  
  Widget _buildTripList(String filterType) {
    final tripProvider = Provider.of<TripProvider>(context);
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    
    if (driverId == null) {
      return const Center(child: Text('Not logged in'));
    }
    
    Query query = FirebaseFirestore.instance.collection('trips')
      .where('driverId', isEqualTo: driverId)
      .orderBy('createdAt', descending: true);
    
    // Apply filters based on tab
    switch (filterType) {
      case 'active':
        query = query.where('status', whereIn: ['accepted', 'arriving', 'arrived', 'inprogress']);
        break;
      case 'completed':
        query = query.where('status', isEqualTo: 'completed');
        break;
      case 'cancelled':
        query = query.where('status', isEqualTo: 'cancelled');
        break;
    }
    
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getEmptyIcon(filterType),
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _getEmptyMessage(filterType),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final tripDoc = snapshot.data!.docs[index];
            final tripData = tripDoc.data() as Map<String, dynamic>;
            
            // Convert Firestore timestamp to DateTime
            final Timestamp? createdTimestamp = tripData['createdAt'];
            final DateTime? createdDate = createdTimestamp?.toDate();
            
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: InkWell(
                onTap: () {
                  // Navigate to trip details
                  // Navigator.push(
                  //   context,
                  //   MaterialPageRoute(
                  //     builder: (context) => TripDetailScreen(
                  //       tripId: tripDoc.id,
                  //     ),
                  //   ),
                  // );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Trip date and status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            createdDate != null 
                                ? _dateFormat.format(createdDate) 
                                : 'Unknown date',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          _buildStatusChip(tripData['status']),
                        ],
                      ),
                      const Divider(),
                      
                      // Pickup and dropoff locations
                      Row(
                        children: [
                          const SizedBox(
                            width: 30,
                            child: Center(
                              child: Icon(
                                Icons.radio_button_on,
                                color: Colors.green,
                                size: 16,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              tripData['pickup']['address'] ?? 'Unknown pickup location',
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      
                      // Show stops if any
                      if (tripData['stops'] != null && 
                          (tripData['stops'] as List).isNotEmpty)
                        ..._buildStopsWidgets(tripData['stops']),
                      
                      Row(
                        children: [
                          const SizedBox(
                            width: 30,
                            child: Center(
                              child: Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 16,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              tripData['dropoff']['address'] ?? 'Unknown destination',
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Trip details (fare, etc.)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(tripData['duration'] ?? 0),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.straighten,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDistance(tripData['distance'] ?? 0),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '\$${(tripData['fare'] ?? 0.0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  List<Widget> _buildStopsWidgets(List stops) {
    return List.generate(
      stops.length,
      (index) => Row(
        children: [
          const SizedBox(
            width: 30,
            child: Center(
              child: Icon(
                Icons.circle,
                color: Colors.orange,
                size: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stops[index]['address'] ?? 'Stop ${index + 1}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String status) {
    Color chipColor;
    String statusText;
    
    switch (status) {
      case 'accepted':
        chipColor = Colors.orange;
        statusText = 'Accepted';
        break;
      case 'arriving':
      case 'arrived':
        chipColor = Colors.amber;
        statusText = status == 'arriving' ? 'On Way' : 'Arrived';
        break;
      case 'inprogress':
        chipColor = Colors.purple;
        statusText = 'In Progress';
        break;
      case 'completed':
        chipColor = Colors.green;
        statusText = 'Completed';
        break;
      case 'cancelled':
        chipColor = Colors.red;
        statusText = 'Cancelled';
        break;
      default:
        chipColor = Colors.grey;
        statusText = status.capitalize();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        border: Border.all(color: chipColor, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  IconData _getEmptyIcon(String filterType) {
    switch (filterType) {
      case 'active':
        return Icons.local_taxi_outlined;
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.history;
    }
  }
  
  String _getEmptyMessage(String filterType) {
    switch (filterType) {
      case 'active':
        return 'No active trips.\nAccept a ride to get started!';
      case 'completed':
        return 'No completed trips yet.\nYour trip history will appear here.';
      case 'cancelled':
        return 'No cancelled trips.\nThat\'s a good thing!';
      default:
        return 'No trips found.';
    }
  }
  
  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    return '$minutes min';
  }
  
  String _formatDistance(double distanceInKm) {
    return '${distanceInKm.toStringAsFixed(1)} km';
  }
}

// Extension method for string capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}