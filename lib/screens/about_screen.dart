import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = 'Loading...';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _getAppInfo();
  }

  Future<void> _getAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      setState(() {
        _version = '1.0.0';
        _buildNumber = '1';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        elevation: 0,
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0), // Reduced from 24
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Add this for better distribution
              children: [
                // App Logo - Made smaller
                Container(
                  width: 80, // Reduced from 120
                  height: 80, // Reduced from 120
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(20), // Reduced from 30
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 15, // Reduced from 20
                        offset: const Offset(0, 8), // Reduced from 10
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 40, // Reduced from 60
                    color: Colors.white,
                  ),
                ),
                
                // App Name
                Text(
                  'Taxi Driver App',
                  style: TextStyle(
                    fontSize: 24, // Reduced from 28
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
                
                // App Version
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Reduced padding
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(16), // Reduced from 20
                  ),
                  child: Text(
                    'Version $_version ($_buildNumber)',
                    style: TextStyle(
                      fontSize: 12, // Reduced from 14
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                
                // Company Info Card - Made smaller
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16), // Reduced from 24
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16), // Reduced from 20
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10, // Reduced from 15
                        offset: const Offset(0, 4), // Reduced from 5
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // MK Pro Logo/Icon - Made smaller
                      Container(
                        width: 60, // Reduced from 80
                        height: 60, // Reduced from 80
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.purple.shade300,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13), // Slightly smaller to account for border
                          child: Image.asset(
                            'assets/images/MKPro.jpg',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.purple.shade400,
                                      Colors.purple.shade600,
                                    ],
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'MK',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 12), // Reduced from 16
                      
                      Text(
                        'Developed by',
                        style: TextStyle(
                          fontSize: 12, // Reduced from 14
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      
                      const SizedBox(height: 2), // Reduced from 4
                      
                      Text(
                        'MK Pro',
                        style: TextStyle(
                          fontSize: 20, // Reduced from 24
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade600,
                        ),
                      ),
                      
                      const SizedBox(height: 4), // Reduced from 8
                      
                      Text(
                        'Professional Mobile App Development',
                        style: TextStyle(
                          fontSize: 10, // Reduced from 12
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                // Features List - Made more compact
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16), // Reduced from 20
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12), // Reduced from 16
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Key Features',
                        style: TextStyle(
                          fontSize: 14, // Reduced from 16
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8), // Reduced from 12
                      _buildFeatureItem('🚕', 'Real-time Trip Management'),
                      _buildFeatureItem('📍', 'GPS Navigation & Tracking'),
                      _buildFeatureItem('💰', 'Earnings Dashboard'),
                      _buildFeatureItem('🔥', 'Hotspot Zones'),
                      _buildFeatureItem('📱', 'Push Notifications'),
                    ],
                  ),
                ),
                
                // Copyright
                Text(
                  '© ${DateTime.now().year} MK Pro. All rights reserved.',
                  style: TextStyle(
                    fontSize: 10, // Reduced from 12
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Update the feature item method to be smaller too
  Widget _buildFeatureItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // Reduced from 8
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 14), // Reduced from 16
          ),
          const SizedBox(width: 8), // Reduced from 12
          Text(
            text,
            style: TextStyle(
              fontSize: 12, // Reduced from 14
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}