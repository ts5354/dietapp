import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == selectedIndex) return;
          context.go(switch (index) {
            0 => '/',
            1 => '/record',
            2 => '/history',
            _ => '/settings',
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Record'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      );
}
