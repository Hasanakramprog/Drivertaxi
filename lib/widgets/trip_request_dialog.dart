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
    // Get expiration time from trip data or default to 20 seconds
    _remainingSeconds = int.tryParse(widget.tripData['expiresIn'] ?? '20') ?? 20;
    
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
    
    return AlertDialog(
      title: Text('New Trip Request (${_remainingSeconds}s)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pickup: ${pickup['address'] ?? 'Unknown location'}'),
          const SizedBox(height: 8),
          Text('Dropoff: ${dropoff['address'] ?? 'Unknown destination'}'),
          const SizedBox(height: 8),
          Text('Distance: ${distance.toString()} km'),
          const SizedBox(height: 8),
          Text('Fare: \$${fare.toString()}'),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _remainingSeconds / (int.tryParse(widget.tripData['expiresIn'] ?? '20') ?? 20),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _rejectTrip,
          child: const Text('REJECT'),
        ),
        ElevatedButton(
          onPressed: _acceptTrip,
          child: const Text('ACCEPT'),
        ),
      ],
    );
  }
}