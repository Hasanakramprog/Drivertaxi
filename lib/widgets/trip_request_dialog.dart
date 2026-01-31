// lib/widgets/trip_request_dialog.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_driver_app/providers/trip_provider.dart';

class TripRequestDialog extends StatefulWidget {
  final Map<String, dynamic> tripData;

  const TripRequestDialog({Key? key, required this.tripData}) : super(key: key);

  @override
  State<TripRequestDialog> createState() => _TripRequestDialogState();
}

class _TripRequestDialogState extends State<TripRequestDialog>
    with TickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _scaleController;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // Start animations
    _scaleController.forward();
    _slideController.forward();

    // Calculate remaining time
    DateTime notificationTime;
    try {
      final timeValue = widget.tripData['notificationTime'];
      if (timeValue != null) {
        if (timeValue is String && timeValue.isNotEmpty) {
          final timestamp = int.tryParse(timeValue);
          if (timestamp != null) {
            notificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          } else {
            notificationTime = DateTime.parse(timeValue);
          }
        } else if (timeValue is int) {
          notificationTime = DateTime.fromMillisecondsSinceEpoch(timeValue);
        } else {
          notificationTime = DateTime.now();
        }
      } else {
        notificationTime = DateTime.now();
      }
    } catch (e) {
      print('Error parsing notification time: $e');
      notificationTime = DateTime.now();
    }

    // Persist notification time to provider if missing to prevent timer reset
    if (widget.tripData['notificationTime'] == null) {
      widget.tripData['notificationTime'] = notificationTime.toIso8601String();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Provider.of<TripProvider>(
            context,
            listen: false,
          ).setCurrentTripRequest(widget.tripData);
        }
      });
    }

    final totalDuration = 60;
    final elapsedSeconds =
        DateTime.now().difference(notificationTime).inSeconds;
    _remainingSeconds = (totalDuration - elapsedSeconds).clamp(
      0,
      totalDuration,
    );

    // If already expired, auto-reject immediately
    if (_remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rejectTrip();
      });
      return;
    }

    // Start countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timer?.cancel();
          _rejectTrip();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _acceptTrip() async {
    HapticFeedback.heavyImpact();
    _timer?.cancel();

    // Clear pickup preview
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    tripProvider.hidePickupPreview();

    // Reverse animation before closing
    await _scaleController.reverse();
    if (mounted) {
      Navigator.of(context).pop();

      tripProvider.acceptTrip(widget.tripData['tripId']);
    }
  }

  void _rejectTrip() async {
    HapticFeedback.mediumImpact();
    _timer?.cancel();

    // Clear pickup preview
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    tripProvider.hidePickupPreview();

    // Reverse animation before closing
    await _scaleController.reverse();
    if (mounted) {
      Navigator.of(context).pop();

      tripProvider.rejectTrip(widget.tripData['tripId']);
    }
  }

  void _toggleMinimize() {
    HapticFeedback.lightImpact();

    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    // Show pickup preview and close dialog
    final pickup = widget.tripData['pickup'] ?? {};
    tripProvider.showPickupPreview(pickup);

    // Close the dialog
    Navigator.of(context).pop();

    // The minimized chip will be shown in home_screen via provider state
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.tripData['pickup'] ?? {};
    final progress = _remainingSeconds / 60.0;
    final isUrgent = _remainingSeconds <= 10;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            decoration: BoxDecoration(
              // Dark glassmorphism background
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1a1a2e).withOpacity(0.95),
                  const Color(0xFF16213e).withOpacity(0.95),
                  const Color(0xFF0f1419).withOpacity(0.98),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              // Neon border glow
              border: Border.all(
                color:
                    isUrgent
                        ? const Color(0xFFff6b6b).withOpacity(0.6)
                        : const Color(0xFF00d4ff).withOpacity(0.6),
                width: 2,
              ),
              // Multiple layered shadows for depth
              boxShadow: [
                // Outer glow
                BoxShadow(
                  color:
                      isUrgent
                          ? const Color(0xFFff6b6b).withOpacity(0.4)
                          : const Color(0xFF00d4ff).withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
                // Deep shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                  spreadRadius: -5,
                ),
                // Inner highlight
                BoxShadow(
                  color: Colors.white.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                  spreadRadius: -5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dark Premium Header
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors:
                              isUrgent
                                  ? [
                                    const Color(0xFF8B0000),
                                    const Color(0xFF660000),
                                    const Color(0xFF4a0000),
                                  ]
                                  : [
                                    const Color(0xFF1e3a8a),
                                    const Color(0xFF1e1b4b),
                                    const Color(0xFF0f0a2e),
                                  ],
                        ),
                      ),
                      child: Column(
                        children: [
                          // Glowing taxi icon
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFffd700).withOpacity(0.3),
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFffd700,
                                    ).withOpacity(0.6),
                                    blurRadius: 30,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_taxi,
                                color: Color(0xFFffd700),
                                size: 48,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Title with glow
                          Text(
                            '🚕 New Trip Request',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.white.withOpacity(0.5),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Neon timer chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color:
                                    isUrgent
                                        ? const Color(0xFFff6b6b)
                                        : const Color(0xFF00d4ff),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      isUrgent
                                          ? const Color(
                                            0xFFff6b6b,
                                          ).withOpacity(0.5)
                                          : const Color(
                                            0xFF00d4ff,
                                          ).withOpacity(0.5),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isUrgent
                                      ? Icons.warning_amber_rounded
                                      : Icons.timer_outlined,
                                  color:
                                      isUrgent
                                          ? const Color(0xFFff6b6b)
                                          : const Color(0xFF00d4ff),
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_remainingSeconds}s',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                    shadows: [
                                      Shadow(
                                        color:
                                            isUrgent
                                                ? const Color(0xFFff6b6b)
                                                : const Color(0xFF00d4ff),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Neon progress bar
                    Container(
                      height: 4,
                      color: Colors.black.withOpacity(0.3),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors:
                                  isUrgent
                                      ? [
                                        const Color(0xFFff6b6b),
                                        const Color(0xFFff8787),
                                      ]
                                      : [
                                        const Color(0xFF00d4ff),
                                        const Color(0xFF0099cc),
                                      ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    isUrgent
                                        ? const Color(0xFFff6b6b)
                                        : const Color(0xFF00d4ff),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Dark content area
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Dark glassmorphism location card
                          _buildDarkLocationCard(
                            icon: Icons.trip_origin,
                            title: 'Pickup Location',
                            address: pickup['address'] ?? 'Unknown location',
                          ),

                          const SizedBox(height: 20),

                          // Neon view map button
                          _buildNeonViewMapButton(),
                        ],
                      ),
                    ),

                    // Neon action buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildNeonActionButton(
                              onPressed: _rejectTrip,
                              label: 'REJECT',
                              icon: Icons.close_rounded,
                              colors: [
                                const Color(0xFFff6b6b),
                                const Color(0xFFff5252),
                                const Color(0xFFff3838),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildNeonActionButton(
                              onPressed: _acceptTrip,
                              label: 'ACCEPT',
                              icon: Icons.check_rounded,
                              colors: [
                                const Color(0xFF00ff88),
                                const Color(0xFF00cc88),
                                const Color(0xFF00aa77),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Dark Glassmorphism Location Card
  Widget _buildDarkLocationCard({
    required IconData icon,
    required String title,
    required String address,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Dark glassmorphism
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00ff88).withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00ff88).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00ff88).withOpacity(0.4),
                  const Color(0xFF00ff88).withOpacity(0.1),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00ff88).withOpacity(0.6),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF00ff88), size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF00d4ff),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF00d4ff).withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Neon View Map Button
  Widget _buildNeonViewMapButton() {
    return InkWell(
      onTap: _toggleMinimize,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFa855f7), Color(0xFF9333ea), Color(0xFF7e22ce)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFa855f7).withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFa855f7).withOpacity(0.5),
              blurRadius: 25,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.map_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'View on Map',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                shadows: [
                  Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Neon Action Button
  Widget _buildNeonActionButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.first.withOpacity(0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: colors.first.withOpacity(0.6),
                blurRadius: 25,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
