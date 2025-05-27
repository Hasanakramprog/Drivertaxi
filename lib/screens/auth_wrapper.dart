import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/auth_provider.dart';
import 'package:taxi_driver_app/screens/authentication/login_screen.dart';
import 'package:taxi_driver_app/screens/home_screen.dart';
import 'package:taxi_driver_app/screens/onboarding/onboarding_screen.dart';
import 'package:taxi_driver_app/services/shared_prefs.dart';
import 'package:taxi_driver_app/widgets/loading.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isFirstLaunch = true;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = SharedPrefs();
    _isFirstLaunch = await prefs.isFirstLaunch();
    
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<DriverAuthProvider>(context);

    // Show loading indicator while checking first launch status
    if (_isChecking) {
      return const LoadingScreen(message: "Setting up...");
    }

    // Show onboarding for first-time users
    if (_isFirstLaunch) {
      return const OnboardingScreen();
    }

    // Handle authentication state
    switch (authProvider.status) {
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        return const HomeScreen();
      case AuthStatus.loading:
      default:
        return const LoadingScreen(message: "Loading...");
    }
  }
}