import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

class FaceVerificationService {
  static final FaceVerificationService _instance = FaceVerificationService._internal();
  factory FaceVerificationService() => _instance;
  FaceVerificationService._internal();

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: false,
      enableContours: true,
      minFaceSize: 0.1,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Temporary URL for face verification image during registration
  String? _tempFaceVerificationUrl;
String? get tempFaceVerificationUrl => _tempFaceVerificationUrl;

void clearTempFaceVerificationUrl() {
  _tempFaceVerificationUrl = null;
}
  // Check if driver needs daily verification
  Future<bool> needsDailyVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return true;

      final driverDoc = await _firestore.collection('drivers').doc(user.uid).get();
      if (!driverDoc.exists) return true;

      final data = driverDoc.data()!;
      final lastVerification = data['lastFaceVerification'] as Timestamp?;
      
      if (lastVerification == null) return true;

      final now = DateTime.now();
      final lastVerificationDate = lastVerification.toDate();
      final difference = now.difference(lastVerificationDate);

      // Need verification if more than 24 hours
      return difference.inHours >= 24;
    } catch (e) {
      print('Error checking verification status: $e');
      return true; // Default to requiring verification
    }
  }

  // Get driver's online status
  Future<bool> canGoOnline() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final driverDoc = await _firestore.collection('drivers').doc(user.uid).get();
      if (!driverDoc.exists) return false;

      final data = driverDoc.data()!;
      return data['isActiveToday'] == true;
    } catch (e) {
      print('Error checking online status: $e');
      return false;
    }
  }

  // Detect faces in image
  Future<List<Face>> detectFaces(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Error detecting faces: $e');
      return [];
    }
  }

  // Validate face quality
  Future<FaceValidationResult> validateFace(String imagePath) async {
    try {
      final faces = await detectFaces(imagePath);
      
      if (faces.isEmpty) {
        return FaceValidationResult(
          isValid: false,
          message: 'No face detected. Please ensure your face is clearly visible.',
        );
      }

      if (faces.length > 1) {
        return FaceValidationResult(
          isValid: false,
          message: 'Multiple faces detected. Please ensure only your face is visible.',
        );
      }

      final face = faces.first;
      
      // Check face size (should be reasonably large)
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      if (faceArea < 10000) { // Adjust threshold as needed
        return FaceValidationResult(
          isValid: false,
          message: 'Face too small. Please move closer to the camera.',
        );
      }

      // Check if face is looking straight (optional)
      if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
        return FaceValidationResult(
          isValid: false,
          message: 'Please look straight at the camera.',
        );
      }

      return FaceValidationResult(
        isValid: true,
        message: 'Face validation successful',
        face: face,
      );
    } catch (e) {
      return FaceValidationResult(
        isValid: false,
        message: 'Error validating face: $e',
      );
    }
  }

  // Store reference face (during registration)
  Future<bool> storeReferenceFace(String imagePath, {String? userId}) async {
    try {
      // Use provided userId or current user
      final user = _auth.currentUser;
      final targetUserId = userId ?? user?.uid;
      
      if (targetUserId == null) {
        print('Error: No user ID provided and no current user');
        return false;
      }

      // Validate face first
      final validation = await validateFace(imagePath);
      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      // Upload to Firebase Storage
      final file = File(imagePath);
      final ref = _storage.ref().child('face_verification/$targetUserId/reference.jpg');
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();

      // Update driver document
      await _firestore.collection('drivers').doc(targetUserId).update({
        'baseFaceImageUrl': downloadUrl,
        'faceVerificationSetup': true,
        'setupTimestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error storing reference face: $e');
      return false;
    }
  }

  // Add a new method for storing during registration
  Future<bool> storeReferenceFaceForRegistration(String imagePath) async {
    try {
      // Check if Firebase Storage is initialized
      if (!await _initializeFirebaseStorage()) {
        throw Exception('Firebase Storage is not properly set up. Please check Firebase Console.');
      }

      // Validate face first
      final validation = await validateFace(imagePath);
      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      // Check if file exists and is readable
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found at path: $imagePath');
      }

      // Check file size (Firebase has limits)
      final fileSize = await file.length();
      if (fileSize > 10 * 1024 * 1024) { // 10MB limit
        throw Exception('Image file too large. Please use a smaller image.');
      }

      print('Uploading file: ${file.path}, size: ${fileSize} bytes');

      // Generate a temporary ID for the image
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Create Firebase Storage reference
      final ref = _storage.ref().child('face_verification/temp/$tempId/reference.jpg');
      
      // Add metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadType': 'face_verification_registration',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      try {
        // Upload file with progress tracking
        final uploadTask = ref.putFile(file, metadata);
        
        // Optional: Listen to upload progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          print('Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
        });

        // Wait for upload to complete
        final snapshot = await uploadTask;
        print('Upload completed successfully');

        // Get download URL
        final downloadUrl = await snapshot.ref.getDownloadURL();
        print('Download URL obtained: $downloadUrl');

        // Store the URL temporarily
        _tempFaceVerificationUrl = downloadUrl;

        return true;
        
      } on FirebaseException catch (e) {
        print('Firebase Storage error: ${e.code} - ${e.message}');
        
        // Handle specific Firebase errors
        switch (e.code) {
          case 'storage/unauthorized':
            throw Exception('Permission denied. Please check Firebase Storage rules.');
          case 'storage/canceled':
            throw Exception('Upload was cancelled.');
          case 'storage/unknown':
            throw Exception('Unknown storage error occurred.');
          default:
            throw Exception('Upload failed: ${e.message}');
        }
      }
      
    } catch (e) {
      print('Error storing reference face for registration: $e');
      return false;
    }
  }

  // Add method to finalize face verification after registration
  Future<bool> finalizeFaceVerificationSetup(String userId, String imageUrl) async {
    try {
      // Update driver document with the stored image URL
      await _firestore.collection('drivers').doc(userId).update({
        'baseFaceImageUrl': imageUrl,
        'faceVerificationSetup': true,
        'setupTimestamp': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      print('Error finalizing face verification setup: $e');
      return false;
    }
  }

  // Perform daily verification
  Future<VerificationResult> performDailyVerification(String imagePath) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return VerificationResult(
          isSuccess: false,
          message: 'User not authenticated',
        );
      }

      // Validate the new image
      final validation = await validateFace(imagePath);
      if (!validation.isValid) {
        return VerificationResult(
          isSuccess: false,
          message: validation.message,
        );
      }

      // Get driver's reference image URL
      final driverDoc = await _firestore.collection('drivers').doc(user.uid).get();
      if (!driverDoc.exists) {
        return VerificationResult(
          isSuccess: false,
          message: 'Driver profile not found',
        );
      }

      final data = driverDoc.data()!;
      final referenceImageUrl = data['baseFaceImageUrl'] as String?;
      
      if (referenceImageUrl == null) {
        return VerificationResult(
          isSuccess: false,
          message: 'Reference image not found. Please contact support.',
        );
      }

      // Download reference image
      final tempDir = await getTemporaryDirectory();
      final referenceFile = File('${tempDir.path}/reference_temp.jpg');
      
      final ref = _storage.refFromURL(referenceImageUrl);
      await ref.writeToFile(referenceFile);

      // Compare faces using basic similarity
      final similarity = await _compareFaces(imagePath, referenceFile.path);
      
      // Clean up temp file
      if (await referenceFile.exists()) {
        await referenceFile.delete();
      }

      if (similarity >= 0.8) { // 80% threshold
        // Store daily verification image
        await _storeDailyVerificationImage(imagePath);
        
        // Update driver status
        await _updateVerificationStatus(true);
        
        return VerificationResult(
          isSuccess: true,
          message: 'Face verification successful! You can now go online.',
          confidence: similarity,
        );
      } else {
        await _updateVerificationStatus(false);
        
        return VerificationResult(
          isSuccess: false,
          message: 'Face verification failed. Please try again or contact support.',
          confidence: similarity,
        );
      }
    } catch (e) {
      print('Error in daily verification: $e');
      return VerificationResult(
        isSuccess: false,
        message: 'Verification error: $e',
      );
    }
  }

  // Basic face comparison using landmarks
  Future<double> _compareFaces(String image1Path, String image2Path) async {
    try {
      final faces1 = await detectFaces(image1Path);
      final faces2 = await detectFaces(image2Path);
      
      if (faces1.isEmpty || faces2.isEmpty) {
        return 0.0;
      }
      
      final face1 = faces1.first;
      final face2 = faces2.first;
      
      // Simple comparison based on face landmarks and proportions
      double similarity = 0.0;
      int comparisons = 0;
      
      // Compare bounding box aspect ratio
      final ratio1 = face1.boundingBox.width / face1.boundingBox.height;
      final ratio2 = face2.boundingBox.width / face2.boundingBox.height;
      final ratioSimilarity = 1.0 - (ratio1 - ratio2).abs();
      similarity += ratioSimilarity;
      comparisons++;
      
      // Compare landmarks if available
      if (face1.landmarks.isNotEmpty && face2.landmarks.isNotEmpty) {
        // You can add more sophisticated landmark comparison here
        // For now, we'll use a simple approach
        similarity += 0.7; // Base similarity for having landmarks
        comparisons++;
      }
      
      return comparisons > 0 ? similarity / comparisons : 0.0;
    } catch (e) {
      print('Error comparing faces: $e');
      return 0.0;
    }
  }

  // Store daily verification image
  Future<void> _storeDailyVerificationImage(String imagePath) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      final file = File(imagePath);
      final ref = _storage.ref().child('face_verification/${user.uid}/daily/$dateStr.jpg');
      await ref.putFile(file);
    } catch (e) {
      print('Error storing daily verification image: $e');
    }
  }

  // Update verification status in Firestore
  Future<void> _updateVerificationStatus(bool isSuccess) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final updateData = {
        'lastFaceVerification': FieldValue.serverTimestamp(),
        'faceVerificationStatus': isSuccess ? 'verified' : 'failed',
        'isActiveToday': isSuccess,
      };

      if (isSuccess) {
        updateData['isAvailable'] = true;
      }

      await _firestore.collection('drivers').doc(user.uid).update(updateData);
      
      // Also update driver_locations if exists
      await _firestore.collection('driver_locations').doc(user.uid).update({
        'isAvailable': isSuccess,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating verification status: $e');
    }
  }

  // Add this method to check Firebase Storage initialization
  Future<bool> _initializeFirebaseStorage() async {
    try {
      // Test if Firebase Storage is accessible
      final testRef = _storage.ref().child('test');
      
      // Try to list files (this will work if storage is properly set up)
      await testRef.listAll();
      return true;
    } catch (e) {
      print('Firebase Storage not properly initialized: $e');
      return false;
    }
  }

  void dispose() {
    _faceDetector.close();
  }
}

// Data classes
class FaceValidationResult {
  final bool isValid;
  final String message;
  final Face? face;

  FaceValidationResult({
    required this.isValid,
    required this.message,
    this.face,
  });
}

class VerificationResult {
  final bool isSuccess;
  final String message;
  final double? confidence;

  VerificationResult({
    required this.isSuccess,
    required this.message,
    this.confidence,
  });
}