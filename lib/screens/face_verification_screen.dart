import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_driver_app/services/face_verification_service.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb and platform detection

class FaceVerificationScreen extends StatefulWidget {
  final bool isSetup; // true for initial setup, false for daily verification

  const FaceVerificationScreen({
    Key? key,
    this.isSetup = false,
  }) : super(key: key);

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  static const bool _forceEmulatorMode = true; // Set to true for testing
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _message;
  File? _selectedImage;
  final FaceVerificationService _verificationService = FaceVerificationService();
  final ImagePicker _imagePicker = ImagePicker();
  
  // Check if running on emulator/web for testing
  // bool get _isEmulatorMode => kDebugMode || kIsWeb;
  bool get _isEmulatorMode => _forceEmulatorMode || kDebugMode || kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!_isEmulatorMode) {
      _initializeCamera();
    } else {
      setState(() {
        _isInitialized = true;
        _message = 'Emulator mode: Use image picker for testing';
      });
    }
  }

  Future<void> _initializeCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _message = 'Camera permission is required for face verification';
      });
      return;
    }

    try {
      // Get available cameras
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _message = 'No cameras available';
        });
        return;
      }

      // Use front camera for selfie
      CameraDescription frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _message = 'Error initializing camera: $e';
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? imageFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1000,
        maxHeight: 1000,
      );
      
      if (imageFile != null) {
        setState(() {
          _selectedImage = File(imageFile.path);
          _message = 'Image selected. Tap verify to process.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error picking image: $e';
      });
    }
  }

  Future<void> _takePictureWithCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      setState(() {
        _selectedImage = File(imageFile.path);
        _message = 'Photo captured. Tap verify to process.';
      });
    } catch (e) {
      setState(() {
        _message = 'Error capturing image: $e';
      });
    }
  }

  Future<void> _processSelectedImage() async {
    if (_selectedImage == null) {
      setState(() {
        _message = 'Please select or capture an image first.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _message = 'Validating image...';
    });

    try {
      if (widget.isSetup) {
        // Update message during upload
        setState(() {
          _message = 'Uploading to secure storage...';
        });
        
        // Store as reference image for registration
        final success = await _verificationService.storeReferenceFaceForRegistration(_selectedImage!.path);
        
        if (success) {
          setState(() {
            _message = 'Face verification setup completed successfully!';
          });
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(true); // Return success
          }
        } else {
          setState(() {
            _message = 'Failed to setup face verification. Please check your internet connection and try again.';
          });
        }
      } else {
        // Perform daily verification
        final result = await _verificationService.performDailyVerification(_selectedImage!.path);
        
        setState(() {
          _message = result.message;
        });
        
        if (result.isSuccess) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        }
      }
    } catch (e) {
      setState(() {
        _message = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSetup ? 'Setup Face Verification' : 'Daily Face Verification'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                Icon(
                  Icons.face,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isSetup 
                      ? _isEmulatorMode 
                          ? 'Select a clear photo of your face for verification setup'
                          : 'Take a clear photo of your face for verification setup'
                      : _isEmulatorMode
                          ? 'Select a photo to verify your identity for today'
                          : 'Take a photo to verify your identity for today',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isEmulatorMode
                      ? '• Choose a clear face photo\n• Ensure good lighting\n• Face should be centered'
                      : '• Look directly at the camera\n• Ensure good lighting\n• Keep your face centered',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isEmulatorMode)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Emulator Mode: Using image picker for testing',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Camera preview or image display
          Expanded(
            child: _buildImageArea(),
          ),
          
          // Message display
          if (_message != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _message!.contains('successful') || _message!.contains('Processing')
                  ? Colors.green.shade100
                  : _message!.contains('Error') || _message!.contains('Failed')
                      ? Colors.red.shade100
                      : Colors.blue.shade100,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _message!.contains('successful') || _message!.contains('Processing')
                      ? Colors.green.shade800
                      : _message!.contains('Error') || _message!.contains('Failed')
                          ? Colors.red.shade800
                          : Colors.blue.shade800,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Action buttons
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_isEmulatorMode) ...[
                  // Image picker buttons for emulator
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _pickImageFromGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Pick Image'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_selectedImage != null && !_isProcessing) 
                              ? _processSelectedImage 
                              : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Verify'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Camera capture and verify buttons for real device
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isInitialized && !_isProcessing) 
                              ? _takePictureWithCamera 
                              : null,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Capture'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_selectedImage != null && !_isProcessing) 
                              ? _processSelectedImage 
                              : null,
                          icon: _isProcessing 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(_isProcessing ? 'Processing...' : 'Verify'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Option to use gallery even on real device
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isProcessing ? null : _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Or pick from gallery'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    if (_selectedImage != null) {
      // Show selected/captured image
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _selectedImage!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (_isEmulatorMode) {
      // Show placeholder for emulator mode
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 2, strokeAlign: BorderSide.strokeAlignInside),
          color: Colors.grey.shade50,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Tap "Pick Image" to select a photo',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show camera preview for real device
    return _buildCameraPreview();
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    if (_message != null && _message!.contains('Error') && _cameraController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _message!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview
        if (_cameraController != null)
          CameraPreview(_cameraController!),
        
        // Face guide overlay
        Center(
          child: Container(
            width: 250,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(150),
            ),
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(130),
              ),
            ),
          ),
        ),
        
        // Instructions overlay
        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Position your face within the oval, then tap Capture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}