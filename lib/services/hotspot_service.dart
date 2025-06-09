import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HotspotService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get hotspots using Cloud Function
  static Future<List<Map<String, dynamic>>> getHotspotsFromFunction() async {
    try {
      final callable = _functions.httpsCallable('getHotspots');
      final result = await callable.call();
      
     final data = Map<String, dynamic>.from(result.data as Map);
      final hotspotsList = data['hotspots'] as List? ?? [];
      
      return hotspotsList.map((hotspot) => Map<String, dynamic>.from(hotspot as Map)).toList();
    } catch (e) {
      print('Error getting hotspots from function: $e');
      return [];
    }
  }
  
  // Get hotspots directly from Firestore (alternative method)
  static Future<List<Map<String, dynamic>>> getHotspotsFromFirestore() async {
    try {
      final snapshot = await _firestore.collection('hotspots').get();
      
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting hotspots from Firestore: $e');
      return [];
    }
  }
  
  // Listen to real-time hotspot updates
  static Stream<List<Map<String, dynamic>>> getHotspotsStream() {
    return _firestore.collection('hotspots').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    });
  }
  
  // Record trip for hotspot calculation
  static Future<void> recordTripForHotspots(Map<String, dynamic> tripData) async {
    try {
      await _firestore.collection('trips').add({
        ...tripData,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error recording trip: $e');
    }
  }
}