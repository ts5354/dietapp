import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppCategory { weight, food, symptom, injection }

extension AppCategoryStyle on AppCategory {
  IconData get icon => switch (this) {
        AppCategory.weight => Icons.monitor_weight_outlined,
        AppCategory.food => Icons.restaurant_outlined,
        AppCategory.symptom => Icons.health_and_safety_outlined,
        AppCategory.injection => Icons.vaccines_outlined,
      };

  Color get color => switch (this) {
        AppCategory.weight => AppColors.weight,
        AppCategory.food => AppColors.food,
        AppCategory.symptom => AppColors.symptom,
        AppCategory.injection => AppColors.injection,
      };

  Color get iconColor => switch (this) {
        AppCategory.weight => const Color(0xFF297A91),
        AppCategory.food => const Color(0xFFB26824),
        AppCategory.symptom => const Color(0xFFA94E62),
        AppCategory.injection => const Color(0xFF7654A6),
      };
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key});

  final AppCategory category;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: category.color,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(category.icon, color: category.iconColor),
      );
}

class CategoryTitle extends StatelessWidget {
  const CategoryTitle(this.category, this.label, {super.key});

  final AppCategory category;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        CategoryIcon(category),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ]);
}
