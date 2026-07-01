import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kinetic/src/theme/app_theme.dart';


/// The main app shell. Manages the bottom navigation bar and tab switching.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // For floating nav bar
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: AppTheme.border.withOpacity(0.5),
                  ),
                ),
                child: BottomNavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  currentIndex: navigationShell.currentIndex,
                  onTap: _goBranch,
                  showSelectedLabels: false,
                  showUnselectedLabels: false,
                  selectedItemColor: AppTheme.primary,
                  unselectedItemColor: AppTheme.textHint,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.language_rounded),
                      activeIcon: Icon(Icons.public_rounded),
                      label: 'Browser',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.manage_accounts_outlined),
                      activeIcon: Icon(Icons.manage_accounts_rounded),
                      label: 'Manage Kin',
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
}
