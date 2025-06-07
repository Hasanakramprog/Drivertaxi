import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:taxi_driver_app/widgets/custom_button.dart';
import 'package:taxi_driver_app/widgets/loading.dart';
import 'package:taxi_driver_app/services/face_verification_service.dart';
import 'package:taxi_driver_app/screens/face_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // Vehicle details controllers
  final _vehicleModelController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _vehicleYearController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _faceVerificationCompleted = false;
  String _errorMessage = '';

  final FaceVerificationService _faceService = FaceVerificationService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
    _licensePlateController.dispose();
    _vehicleYearController.dispose();
    super.dispose();
  }

  Future<void> _setupFaceVerification() async {
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const FaceVerificationScreen(isSetup: true),
        ),
      );
      
      if (result == true) {
        setState(() {
          _faceVerificationCompleted = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face verification setup completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error setting up face verification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Update your _register method in register_screen.dart
Future<void> _register() async {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  // Check if face verification is completed
  if (!_faceVerificationCompleted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please complete face verification setup before registering.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  setState(() {
    _isLoading = true;
    _errorMessage = '';
  });

  try {
    final authProvider = Provider.of<DriverAuthProvider>(context, listen: false);
    
    // ✅ Get the stored face verification URL from the service
    final faceService = FaceVerificationService();
    final faceVerificationUrl = faceService.tempFaceVerificationUrl;
    
    if (faceVerificationUrl == null) {
      throw 'Face verification image not found. Please complete face verification again.';
    }
    
    print('Using face verification URL: $faceVerificationUrl'); // Debug log
    
    // Create vehicle details map
    final vehicleDetails = {
      'model': _vehicleModelController.text.trim(),
      'color': _vehicleColorController.text.trim(),
      'licensePlate': _licensePlateController.text.trim(),
      'year': _vehicleYearController.text.trim(),
    };
    
    // ✅ Call the new registration method with face verification URL
    await authProvider.registerDriverWithFaceVerification(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      vehicleDetails: vehicleDetails,
      faceVerificationImageUrl: faceVerificationUrl, // ✅ Pass the stored URL
    );
    
    // ✅ Clear the temporary URL after successful registration
    faceService.clearTempFaceVerificationUrl();
    
    if (mounted) {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration successful! Face verification is setup. Please wait for approval.'),
          duration: Duration(seconds: 3),
        ),
      );
      
      await Future.delayed(const Duration(seconds: 1));
      Navigator.pop(context);
    }
  } catch (e) {
    setState(() {
      _errorMessage = e.toString();
    });
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Registration'),
        elevation: 0,
      ),
      body: _isLoading
          ? const LoadingScreen(message: "Creating your account...")
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Create Your Driver Account',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        
                        // Personal Information Section
                        _buildSectionHeader('Personal Information'),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                .hasMatch(value)) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your phone number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: !_isConfirmPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isConfirmPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                        
                        // Face Verification Section
                        _buildSectionHeader('Face Verification Setup'),
                        const SizedBox(height: 16),
                        
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _faceVerificationCompleted 
                                ? Colors.green.shade50 
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _faceVerificationCompleted 
                                  ? Colors.green.shade300 
                                  : Colors.blue.shade300,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _faceVerificationCompleted 
                                        ? Icons.check_circle 
                                        : Icons.face,
                                    color: _faceVerificationCompleted 
                                        ? Colors.green 
                                        : Colors.blue,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _faceVerificationCompleted 
                                              ? 'Face Verification Setup Complete'
                                              : 'Setup Face Verification',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _faceVerificationCompleted 
                                                ? Colors.green.shade700 
                                                : Colors.blue.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _faceVerificationCompleted 
                                              ? 'Your face verification has been setup successfully. You\'ll need to verify daily to go online.'
                                              : 'For security, we need to setup face verification. This will be used for daily identity checks.',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (!_faceVerificationCompleted) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _setupFaceVerification,
                                    icon: const Icon(Icons.face),
                                    label: const Text('Setup Face Verification'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Vehicle Information Section
                        _buildSectionHeader('Vehicle Information'),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _vehicleModelController,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle Model',
                            prefixIcon: Icon(Icons.directions_car),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your vehicle model';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _vehicleYearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle Year',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your vehicle year';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _vehicleColorController,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle Color',
                            prefixIcon: Icon(Icons.color_lens),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your vehicle color';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _licensePlateController,
                          decoration: const InputDecoration(
                            labelText: 'License Plate',
                            prefixIcon: Icon(Icons.confirmation_number),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your license plate number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        
                        if (_errorMessage.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            color: Colors.red.shade100,
                            child: Text(
                              _errorMessage,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        const SizedBox(height: 24),
                        
                        CustomButton(
                          text: 'Register as Driver',
                          onPressed: _register,
                          color: _faceVerificationCompleted 
                              ? Theme.of(context).primaryColor 
                              : Colors.grey,
                        ),
                        
                        if (!_faceVerificationCompleted)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Please complete face verification setup to proceed with registration.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        const SizedBox(height: 16),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Already have an account?"),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text('Login'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Divider(thickness: 1.5),
      ],
    );
  }
}