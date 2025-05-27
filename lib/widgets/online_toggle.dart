// lib/widgets/online_toggle.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:taxi_driver_app/main.dart'; // Import to access navigatorKey

class OnlineToggle extends StatelessWidget {
  const OnlineToggle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Store the context from the build method
    final currentContext = context;
    
    return Consumer<LocationProvider>(
      builder: (context, locationProvider, _) {
        final bool isOnline = locationProvider.isOnline;
        
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isOnline ? 'You are online' : 'You are offline',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    Switch(
                      value: isOnline,
                      activeColor: Colors.green,
                      onChanged: (value) => _toggleOnlineStatus(value, currentContext),
                    ),
                  ],
                ),
                if (!isOnline)
                  const Text(
                    'Go online to start receiving trip requests',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _toggleOnlineStatus(bool value, BuildContext context) {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    
    if (value) {
      locationProvider.goOnline(context);
    } else {
      // Confirm going offline
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Go Offline?'),
          content: const Text(
            'You will stop receiving trip requests. Are you sure you want to go offline?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                locationProvider.goOffline();
                Navigator.pop(dialogContext);
              },
              child: const Text('Go Offline'),
            ),
          ],
        ),
      );
    }
  }
}