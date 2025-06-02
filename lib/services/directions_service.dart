import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DirectionsService {
  // Replace with your actual API key
  static const String _apiKey = 'AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis';
  
  Future<Directions?> getDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?'
      'origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&key=$_apiKey',
    );
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check if the response has routes
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          return Directions.fromMap(data);
        }
        return null;
      }
      throw Exception('Failed to fetch directions');
    } catch (e) {
      print('Error fetching directions: $e');
      return null;
    }
  }

  Future<List<Directions?>> getDirectionsWithStops({
    required LatLng origin,
    required List<LatLng> stops,
    required LatLng destination,
  }) async {
    List<Directions?> allDirections = [];
    
    // First leg: origin to first stop
    if (stops.isNotEmpty) {
      final firstLeg = await getDirections(
        origin: origin,
        destination: stops.first,
      );
      allDirections.add(firstLeg);
      
      // Middle legs: between stops
      for (int i = 0; i < stops.length - 1; i++) {
        final leg = await getDirections(
          origin: stops[i],
          destination: stops[i + 1],
        );
        allDirections.add(leg);
      }
      
      // Last leg: last stop to destination
      final lastLeg = await getDirections(
        origin: stops.last,
        destination: destination,
      );
      allDirections.add(lastLeg);
    } else {
      // No stops, just origin to destination
      final directRoute = await getDirections(
        origin: origin,
        destination: destination,
      );
      allDirections.add(directRoute);
    }
    
    return allDirections;
  }
}

class Directions {
  final List<PointLatLng> polylinePoints;
  final String totalDistance;
  final String totalDuration;
  
  const Directions({
    required this.polylinePoints,
    required this.totalDistance,
    required this.totalDuration,
  });
  
  factory Directions.fromMap(Map<String, dynamic> map) {
    // Get route information
    final data = map['routes'][0];
    
    // Get leg information
    final leg = data['legs'][0];
    final distance = leg['distance']['text'];
    final duration = leg['duration']['text'];
    
    // Get encoded polyline points
    final points = data['overview_polyline']['points'];
    final polylinePoints = PolylinePoints().decodePolyline(points);
    
    return Directions(
      polylinePoints: polylinePoints,
      totalDistance: distance,
      totalDuration: duration,
    );
  }
}