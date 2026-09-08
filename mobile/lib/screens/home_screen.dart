import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('dietapp')),
      body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Health logging is ready to begin.'),
        const Text('記録する'),
        FilledButton(
            onPressed: () => context.go('/record/weight'),
            child: const Text('体重')),
        FilledButton(
            onPressed: () => context.go('/record/food'),
            child: const Text('食事')),
        FilledButton(
            onPressed: () => context.go('/record/symptom'),
            child: const Text('体調')),
        FilledButton(
            onPressed: () => context.go('/record/injection'),
            child: const Text('注射')),
      ])),
    );
  }
}
