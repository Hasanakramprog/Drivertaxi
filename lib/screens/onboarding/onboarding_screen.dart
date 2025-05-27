import 'package:flutter/material.dart';
import 'package:taxi_driver_app/screens/authentication/login_screen.dart';
import 'package:taxi_driver_app/services/shared_prefs.dart';
import 'package:taxi_driver_app/widgets/custom_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Welcome to Taxi Driver App',
      description: 'The easiest way to earn money driving your own car',
      image: 'assets/images/onboarding1.png',
      color: Colors.blue,
    ),
    OnboardingPage(
      title: 'Flexible Schedule',
      description: 'Work whenever you want, be your own boss',
      image: 'assets/images/onboarding2.png',
      color: Colors.orange,
    ),
    OnboardingPage(
      title: 'Track Earnings',
      description: 'See your daily, weekly and monthly earnings at a glance',
      image: 'assets/images/onboarding3.png',
      color: Colors.green,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finishOnboarding() async {
    final prefs = SharedPrefs();
    await prefs.setFirstLaunchComplete();
    
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _buildPageIndicator(),
                    ),
                    const SizedBox(height: 20),
                    CustomButton(
                      text: _currentPage == _pages.length - 1 
                          ? 'Get Started' 
                          : 'Next',
                      onPressed: _currentPage == _pages.length - 1
                          ? _finishOnboarding
                          : () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeIn,
                              );
                            },
                      color: _pages[_currentPage].color,
                    ),
                    if (_currentPage < _pages.length - 1)
                      TextButton(
                        onPressed: _finishOnboarding,
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image.asset(
          //   page.image,
          //   height: 240,
          // ),
          const SizedBox(height: 40),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageIndicator() {
    List<Widget> indicators = [];
    for (int i = 0; i < _pages.length; i++) {
      indicators.add(
        Container(
          width: 8.0,
          height: 8.0,
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == _currentPage 
                ? _pages[i].color 
                : Colors.grey[300],
          ),
        ),
      );
    }
    return indicators;
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final String image;
  final Color color;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.image,
    required this.color,
  });
}