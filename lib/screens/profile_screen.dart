// TODO Implement this library.// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_driver_app/screens/authentication/login_screen.dart'; // Add this import

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleYearController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _licensePlateController = TextEditingController();
  
  bool _isLoading = false;
  bool _isEditing = false;
  Map<String, dynamic> _driverData = {};
  
  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleYearController.dispose();
    _vehicleColorController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }
  
  Future<void> _loadDriverData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final driverId = FirebaseAuth.instance.currentUser?.uid;
      if (driverId == null) return;
      
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();
      
      if (driverDoc.exists) {
        _driverData = driverDoc.data() as Map<String, dynamic>;
        
        // Initialize controllers
        _nameController.text = _driverData['displayName'] ?? '';
        _phoneController.text = _driverData['phoneNumber'] ?? '';
        
        final vehicleDetails = _driverData['vehicleDetails'] as Map<String, dynamic>? ?? {};
        _vehicleMakeController.text = vehicleDetails['make'] ?? '';
        _vehicleModelController.text = vehicleDetails['model'] ?? '';
        _vehicleYearController.text = vehicleDetails['year']?.toString() ?? '';
        _vehicleColorController.text = vehicleDetails['color'] ?? '';
        _licensePlateController.text = vehicleDetails['licensePlate'] ?? '';
      }
    } catch (e) {
      print('Error loading driver data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final driverId = FirebaseAuth.instance.currentUser?.uid;
      if (driverId == null) return;
      
      // Update vehicle details
      final vehicleDetails = {
        'make': _vehicleMakeController.text.trim(),
        'model': _vehicleModelController.text.trim(),
        'year': int.tryParse(_vehicleYearController.text.trim()) ?? 0,
        'color': _vehicleColorController.text.trim(),
        'licensePlate': _licensePlateController.text.trim(),
      };
      
      // Update driver document
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .update({
        'displayName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'vehicleDetails': vehicleDetails,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update user display name
      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        _nameController.text.trim(),
      );
      
      setState(() {
        _isEditing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      print('Error updating profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<DriverAuthProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile header
                  Center(
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 50,
                          child: Icon(Icons.person, size: 50),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _driverData['displayName'] ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          authProvider.user?.email ?? '',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star, color: Colors.amber[700], size: 20),
                            Text(
                              ' ${_driverData['rating']?.toStringAsFixed(1) ?? '5.0'} • ',
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              '${_driverData['ratingCount'] ?? 0} ratings',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  
                  // Status indicator
                  ListTile(
                    leading: Icon(
                      _driverData['isApproved'] == true
                          ? Icons.check_circle
                          : Icons.pending,
                      color: _driverData['isApproved'] == true
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: const Text('Account Status'),
                    subtitle: Text(
                      _driverData['isApproved'] == true
                          ? 'Approved'
                          : 'Pending Approval',
                    ),
                  ),
                  
                  const Divider(),
                  
                  // Stats
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem(
                          'Trips',
                          '${_driverData['tripCount'] ?? 0}',
                          Icons.directions_car,
                        ),
                        _buildStatItem(
                          'Earnings',
                          '\$${(_driverData['totalEarnings'] ?? 0).toStringAsFixed(2)}',
                          Icons.attach_money,
                        ),
                        _buildStatItem(
                          'Member Since',
                          _formatDate(_driverData['createdAt']),
                          Icons.calendar_today,
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(),
                  
                  // Profile form
                  _isEditing
                      ? _buildEditForm()
                      : _buildProfileInfo(),
                  
                  const SizedBox(height: 16),
                  
                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Show confirmation dialog
                        final shouldLogout = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to logout?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Logout'),
                              ),
                            ],
                          ),
                        ) ?? false;
                        
                        if (shouldLogout) {
                          try {
                            await authProvider.logout();
                            
                            // Navigate to login screen and remove all previous routes
                            if (mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                                (route) => false, // This removes all previous routes
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error logging out: $e')),
                              );
                            }
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.month}/${date.year}';
    }
    
    return 'N/A';
  }
  
  Widget _buildProfileInfo() {
    final vehicleDetails = _driverData['vehicleDetails'] as Map<String, dynamic>? ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Information',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoItem('Full Name', _driverData['displayName'] ?? 'Not provided'),
        _buildInfoItem('Phone Number', _driverData['phoneNumber'] ?? 'Not provided'),
        
        const SizedBox(height: 16),
        const Text(
          'Vehicle Information',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoItem('Make', vehicleDetails['make'] ?? 'Not provided'),
        _buildInfoItem('Model', vehicleDetails['model'] ?? 'Not provided'),
        _buildInfoItem('Year', vehicleDetails['year']?.toString() ?? 'Not provided'),
        _buildInfoItem('Color', vehicleDetails['color'] ?? 'Not provided'),
        _buildInfoItem('License Plate', vehicleDetails['licensePlate'] ?? 'Not provided'),
      ],
    );
  }
  
  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          const Text(
            'Vehicle Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vehicleMakeController,
            decoration: const InputDecoration(
              labelText: 'Make',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter vehicle make';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vehicleModelController,
            decoration: const InputDecoration(
              labelText: 'Model',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter vehicle model';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vehicleYearController,
            decoration: const InputDecoration(
              labelText: 'Year',
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter vehicle year';
              }
              if (int.tryParse(value) == null) {
                return 'Please enter a valid year';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vehicleColorController,
            decoration: const InputDecoration(
              labelText: 'Color',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter vehicle color';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _licensePlateController,
            decoration: const InputDecoration(
              labelText: 'License Plate',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter license plate';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _isEditing = false;
                    // Reset controllers to original values
                    _loadDriverData();
                  });
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _updateProfile,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}