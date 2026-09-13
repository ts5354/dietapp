import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/category_icon.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('記録')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _RecordDestination(
              category: AppCategory.weight,
              label: '体重',
              description: '今日の体重を記録',
              route: '/record/weight',
            ),
            _RecordDestination(
              category: AppCategory.food,
              label: '食事',
              description: '食べたものを記録',
              route: '/record/food',
            ),
            _RecordDestination(
              category: AppCategory.symptom,
              label: '体調',
              description: '今日の状態を記録',
              route: '/record/symptom',
            ),
            _RecordDestination(
              category: AppCategory.injection,
              label: '注射',
              description: '注射の記録',
              route: '/record/injection',
            ),
          ],
        ),
      );
}

class _RecordDestination extends StatelessWidget {
  const _RecordDestination({
    required this.category,
    required this.label,
    required this.description,
    required this.route,
  });

  final AppCategory category;
  final String label;
  final String description;
  final String route;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          minVerticalPadding: 14,
          leading: CategoryIcon(category),
          title: Text(label),
          subtitle: Text(description),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        ),
      );
}
