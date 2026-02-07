// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:taxi_driver_app/providers/location_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_driver_app/screens/authentication/login_screen.dart';
import 'package:taxi_driver_app/models/driver.dart';
import 'package:taxi_driver_app/widgets/driver_metrics_widgets.dart';

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
  final _licensePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;
  bool _isImageLoading = true; // Add this for image loading state
  Driver? _driver;

  double _todayEarnings = 0.0;
  int _todayTrips = 0;

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

      final driverDoc =
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverId)
              .get();

      if (driverDoc.exists) {
        _driver = Driver.fromFirestore(driverDoc);

        // Initialize controllers
        _nameController.text = _driver!.displayName;
        _phoneController.text = _driver!.phoneNumber;

        _vehicleMakeController.text = _driver!.vehicleDetails.make;
        _vehicleModelController.text = _driver!.vehicleDetails.model;
        _vehicleYearController.text =
            _driver!.vehicleDetails.year > 0
                ? _driver!.vehicleDetails.year.toString()
                : '';
        _licensePlateController.text = _driver!.vehicleDetails.licensePlate;
        _vehicleColorController.text = _driver!.vehicleDetails.color;
      }

      // Load today's stats
      await _loadTodayStats();
    } catch (e) {
      print('Error loading driver data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTodayStats() async {
    try {
      final driverId = FirebaseAuth.instance.currentUser?.uid;
      if (driverId == null) return;

      // Get today's date range
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Query trips for today
      final tripsQuery =
          await FirebaseFirestore.instance
              .collection('trips')
              .where('driverId', isEqualTo: driverId)
              .where('status', isEqualTo: 'completed')
              .where(
                'completionTime',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
              )
              .where('completionTime', isLessThan: Timestamp.fromDate(todayEnd))
              .get();

      double totalEarnings = 0.0;
      int tripCount = 0;

      for (var doc in tripsQuery.docs) {
        final tripData = doc.data();
        final fare = (tripData['fare'] as num?)?.toDouble() ?? 0.0;
        totalEarnings += fare;
        tripCount++;
      }

      if (mounted) {
        setState(() {
          _todayEarnings = totalEarnings;
          _todayTrips = tripCount;
        });
      }
    } catch (e) {
      print('Error loading today stats: $e');
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildProfileImage() {
    final profileImageUrl = _driver?.baseFaceImageUrl;

    return Stack(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: Colors.grey[300],
          backgroundImage:
              profileImageUrl != null && profileImageUrl.isNotEmpty
                  ? NetworkImage(profileImageUrl)
                  : null,
          child:
              profileImageUrl == null || profileImageUrl.isEmpty
                  ? const Icon(Icons.person, size: 50)
                  : null,
        ),
        // Loading overlay
        if (_isImageLoading &&
            profileImageUrl != null &&
            profileImageUrl.isNotEmpty)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileImageWithListener() {
    final profileImageUrl = _driver?.baseFaceImageUrl;

    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey[300],
        child: const Icon(Icons.person, size: 50),
      );
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: Colors.grey[300],
          backgroundImage: NetworkImage(profileImageUrl),
          onBackgroundImageError: (exception, stackTrace) {
            print('Error loading profile image: $exception');
            if (mounted) {
              setState(() {
                _isImageLoading = false;
              });
            }
          },
        ),
        // Loading overlay
        if (_isImageLoading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Alternative approach using Image.network with proper loading handling
  Widget _buildProfileImageAdvanced() {
    final profileImageUrl = _driver?.baseFaceImageUrl;

    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey[300],
        child: const Icon(Icons.person, size: 50),
      );
    }

    return SizedBox(
      width: 100,
      height: 100,
      child: ClipOval(
        child: Image.network(
          profileImageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              // Image loaded successfully
              return child;
            }

            // Show loading indicator while image is loading
            return Container(
              color: Colors.grey[300],
              child: Center(
                child: CircularProgressIndicator(
                  value:
                      loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                  strokeWidth: 2,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            print('Error loading profile image: $error');
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.person, size: 50, color: Colors.grey),
            );
          },
        ),
      ),
    );
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
      body:
          _isLoading
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
                          _buildProfileImageAdvanced(),
                          const SizedBox(height: 8),
                          Text(
                            _driver?.displayName ?? 'Driver',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _driver?.email ?? authProvider.user?.email ?? '',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star,
                                color: Colors.amber[700],
                                size: 20,
                              ),
                              Text(
                                ' ${_driver?.formattedRating ?? '5.0'} • ',
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text(
                                '${_driver?.ratingCount ?? 0} ratings',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          // Add Tier Badge
                          if (_driver?.metrics != null) ...[
                            const SizedBox(height: 12),
                            TierBadgeWidget(driver: _driver!),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // Driver Metrics Dashboard
                    if (_driver?.metrics != null) ...[
                      MetricsDashboardWidget(driver: _driver!),
                      const SizedBox(height: 16),
                    ],
                    const Divider(),

                    // Status indicator
                    ListTile(
                      leading: Icon(
                        _driver?.isApproved == true
                            ? Icons.check_circle
                            : Icons.pending,
                        color:
                            _driver?.isApproved == true
                                ? Colors.green
                                : Colors.orange,
                      ),
                      title: const Text('Account Status'),
                      subtitle: Text(
                        _driver?.isApproved == true
                            ? 'Approved'
                            : 'Pending Approval',
                      ),
                    ),

                    const Divider(),

                    // Today's Stats Section
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        children: [
                          Text(
                            'Today\'s Performance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem(
                                'Today\'s Trips',
                                '$_todayTrips',
                                Icons.directions_car,
                                Colors.blue,
                              ),
                              _buildStatItem(
                                'Today\'s Earnings',
                                '\$${_todayEarnings.toStringAsFixed(2)}',
                                Icons.attach_money,
                                Colors.green,
                              ),
                              _buildStatItem(
                                'Member Since',
                                _driver?.memberSince ?? 'N/A',
                                Icons.calendar_today,
                                Colors.orange,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(),

                    // Profile form
                    _isEditing ? _buildEditForm() : _buildProfileInfo(),

                    const SizedBox(height: 16),

                    // Logout button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Show confirmation dialog
                          final shouldLogout =
                              await showDialog<bool>(
                                context: context,
                                builder:
                                    (context) => AlertDialog(
                                      title: const Text('Logout'),
                                      content: const Text(
                                        'Are you sure you want to logout?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.of(
                                                context,
                                              ).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed:
                                              () => Navigator.of(
                                                context,
                                              ).pop(true),
                                          child: const Text('Logout'),
                                        ),
                                      ],
                                    ),
                              ) ??
                              false;

                          if (shouldLogout) {
                            try {
                              // Get location provider to set driver offline
                              final locationProvider =
                                  Provider.of<LocationProvider>(
                                    context,
                                    listen: false,
                                  );

                              // Set driver offline first if currently online
                              if (locationProvider.isOnline) {
                                print(
                                  'Setting driver offline before logout...',
                                );
                                await locationProvider.goOffline();
                              }

                              // Then logout
                              await authProvider.logout();

                              // Navigate to login screen and remove all previous routes
                              if (mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                  (route) =>
                                      false, // This removes all previous routes
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error logging out: $e'),
                                  ),
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

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfo() {
    if (_driver == null) {
      return const Center(child: Text('No driver data available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoItem('Full Name', _driver!.displayName),
        _buildInfoItem('Phone Number', _driver!.phoneNumber),

        const SizedBox(height: 16),
        const Text(
          'Vehicle Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoItem('Make', _driver!.vehicleDetails.make),
        _buildInfoItem('Model', _driver!.vehicleDetails.model),
        _buildInfoItem(
          'Year',
          _driver!.vehicleDetails.year > 0
              ? _driver!.vehicleDetails.year.toString()
              : 'Not provided',
        ),
        _buildInfoItem('Color', _driver!.vehicleDetails.color),
        _buildInfoItem('License Plate', _driver!.vehicleDetails.licensePlate),
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
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
            decoration: const InputDecoration(labelText: 'Phone Number'),
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vehicleMakeController,
            decoration: const InputDecoration(labelText: 'Make'),
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
            decoration: const InputDecoration(labelText: 'Model'),
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
            decoration: const InputDecoration(labelText: 'Year'),
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
            decoration: const InputDecoration(labelText: 'Color'),
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
            decoration: const InputDecoration(labelText: 'License Plate'),
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
                child:
                    _isLoading
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
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
