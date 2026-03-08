/// Main Pager — horizontal PageView wrapping Camera and Statistics.
///
/// Always opens on the Camera page (index 0).
/// Two small dot indicators at the very bottom show the current page.
/// In RTL (Hebrew) the camera is on the right; swipe left → Statistics.

import 'package:flutter/material.dart';
import 'camera_capture_screen.dart';
import 'statistics_screen.dart';

class MainPagerScreen extends StatefulWidget {
  const MainPagerScreen({super.key});

  @override
  State<MainPagerScreen> createState() => _MainPagerScreenState();
}

class _MainPagerScreenState extends State<MainPagerScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: const [
              CameraCaptureScreen(),
              StatisticsScreen(),
            ],
          ),

          // Dot indicators at the very bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dot(0),
                    const SizedBox(width: 8),
                    _dot(1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int index) {
    final isActive = _currentPage == index;
    // Camera page has a dark background → white dots.
    // Statistics page has a light background → dark dots.
    final onDarkBg = _currentPage == 0;
    final activeColor = onDarkBg ? Colors.white : Colors.black87;
    final inactiveColor = onDarkBg
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? activeColor : inactiveColor,
      ),
    );
  }
}
