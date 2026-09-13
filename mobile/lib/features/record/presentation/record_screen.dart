import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('記録')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RecordDestination(
              icon: Icons.monitor_weight_outlined,
              label: '体重',
              onTap: () => context.push('/record/weight'),
            ),
            _RecordDestination(
              icon: Icons.restaurant_outlined,
              label: '食事',
              onTap: () => context.push('/record/food'),
            ),
            _RecordDestination(
              icon: Icons.health_and_safety_outlined,
              label: '体調',
              onTap: () => context.push('/record/symptom'),
            ),
            _RecordDestination(
              icon: Icons.vaccines_outlined,
              label: '注射',
              onTap: () => context.push('/record/injection'),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (index) {
            if (index == 0) context.go('/');
            if (index == 2) context.go('/history');
            if (index == 3) context.go('/settings');
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              label: 'Record',
            ),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      );
}

class _RecordDestination extends StatelessWidget {
  const _RecordDestination({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
