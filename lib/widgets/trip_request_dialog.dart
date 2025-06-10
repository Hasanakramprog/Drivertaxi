// lib/widgets/trip_request_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';

class TripRequestDialog extends StatefulWidget {
  final Map<String, dynamic> tripData;
  
  const TripRequestDialog({
    Key? key, 
    required this.tripData,
  }) : super(key: key);

  @override
  State<TripRequestDialog> createState() => _TripRequestDialogState();
}

class _TripRequestDialogState extends State<TripRequestDialog> {
  late int _remainingSeconds;
  Timer? _timer;
  
  @override
  void initState() {
    super.initState();
    
     // Calculate remaining time based on when notification was received
  DateTime notificationTime;
  try {
    final timeValue = widget.tripData['notificationTime'];
    if (timeValue != null) {
      if (timeValue is String && timeValue.isNotEmpty) {
        // Try parsing as milliseconds timestamp first
        final timestamp = int.tryParse(timeValue);
        if (timestamp != null) {
          notificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        } else {
          // Fallback to ISO8601 string parsing
          notificationTime = DateTime.parse(timeValue);
        }
      } else if (timeValue is int) {
        // Direct integer timestamp
        notificationTime = DateTime.fromMillisecondsSinceEpoch(timeValue);
      } else {
        notificationTime = DateTime.now();
      }
    } else {
      // Fallback to current time if no valid timestamp
      notificationTime = DateTime.now();
    }
  } catch (e) {
    // If parsing fails, use current time as fallback
    print('Error parsing notification time: $e');
    notificationTime = DateTime.now();
  }
    final totalDuration = int.tryParse(widget.tripData['expiresIn'] ?? '20') ?? 20;
    final elapsedSeconds = DateTime.now().difference(notificationTime).inSeconds;
    
    _remainingSeconds = (totalDuration - elapsedSeconds).clamp(0, totalDuration);
    
    // If already expired, auto-reject immediately
    if (_remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rejectTrip();
      });
      return;
    }
    
    // Start countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          // Auto-reject when timer expires
          _timer?.cancel();
          _rejectTrip();
        }
      });
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  
  void _acceptTrip() {
    _timer?.cancel();
    Navigator.of(context).pop();
    
    // Get trip provider
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    // Call method to accept trip
    tripProvider.acceptTrip(widget.tripData['tripId']);
  }
  
  void _rejectTrip() {
    _timer?.cancel();
    Navigator.of(context).pop();
    
    // Get trip provider
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    // Call method to reject trip
    tripProvider.rejectTrip(widget.tripData['tripId']);
  }
  
@override
Widget build(BuildContext context) {
  final pickup = widget.tripData['pickup'] ?? {};
  final dropoff = widget.tripData['dropoff'] ?? {};
  final fare = widget.tripData['fare'] ?? 0.0;
  final distance = widget.tripData['distance'] ?? 0.0;
  final hasStops = widget.tripData['hasStops'] == true;
  final stops = (widget.tripData['stops'] as List<dynamic>?) ?? [];
  final totalWaitingTime = widget.tripData['totalWaitingTime'] ?? 0;
  
  return AlertDialog(
    title: Text('New Trip Request (${_remainingSeconds}s)'),
    content: SizedBox( // Set a constrained width
      width: MediaQuery.of(context).size.width * 0.8, // 80% of screen width
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pickup
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Pickup: ${pickup['address'] ?? 'Unknown location'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis, // Handle text overflow
                    maxLines: 2, // Allow 2 lines for address
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Stops (if present)
            if (hasStops && stops.isNotEmpty) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.more_vert, color: Colors.orange, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    'Stops (${stops.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              
              // List stops with waiting time
              ...stops.map((stop) {
                final waitingTime = stop['waitingTime'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          stop['address'] ?? 'Unknown stop',
                          overflow: TextOverflow.ellipsis, // Handle text overflow
                          maxLines: 2, // Allow 2 lines for address
                        ),
                      ),
                      if (waitingTime > 0)
                        Text(
                          '${waitingTime} min',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              
              if (totalWaitingTime > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: Text(
                    'Total waiting: $totalWaitingTime min',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Divider(height: 16),
            ],
            
            // Dropoff
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Dropoff: ${dropoff['address'] ?? 'Unknown destination'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis, // Handle text overflow
                    maxLines: 2, // Allow 2 lines for address
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Trip details - Wrap this in a Column instead of Row to prevent overflow
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Distance: ${distance.toString()} km'),
                const SizedBox(height: 4),
                Text('Fare: \$${fare.toString()}'),
              ],
            ),
            const SizedBox(height: 16),
            
            LinearProgressIndicator(
              value: _remainingSeconds / (int.tryParse(widget.tripData['expiresIn'] ?? '20') ?? 20),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _rejectTrip,
        style: TextButton.styleFrom(
          foregroundColor: Colors.red,
        ),
        child: const Text('REJECT'),
      ),
      ElevatedButton(
        onPressed: _acceptTrip,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
        ),
        child: const Text('ACCEPT'),
      ),
    ],
  );
}
}