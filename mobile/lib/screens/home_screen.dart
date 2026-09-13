import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/domain/dashboard.dart';
import '../features/dashboard/providers/dashboard_provider.dart';
import '../shared/presentation/category_icon.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final state = ref.read(dashboardControllerProvider);
      final controller = ref.read(dashboardControllerProvider.notifier);
      if (state.dashboard == null) {
        controller.load(DateTime.now());
      } else {
        controller.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ホーム')),
      body: RefreshIndicator(
        onRefresh: ref.read(dashboardControllerProvider.notifier).refresh,
        child: ListView(
          key: const Key('dashboardScroll'),
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _naturalDate(state.date),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: state.mode == DashboardViewMode.loading
                  ? null
                  : () => _selectDate(state.date),
            ),
            if (state.dashboard case final dashboard?) ...[
              if (state.mode == DashboardViewMode.error) ...[
                Text(state.message ?? 'ホーム情報の更新中にエラーが発生しました。'),
                TextButton(
                  key: const Key('retryDashboardButton'),
                  onPressed:
                      ref.read(dashboardControllerProvider.notifier).refresh,
                  child: const Text('再読み込み'),
                ),
              ],
              _NextInjection(
                dashboard.injection.nextScheduledDate,
                state.date,
              ),
              const SizedBox(height: 24),
              Text('今日の記録', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _WeightCard(dashboard.weight, () => _open('/record/weight')),
              _NutritionCard(dashboard.nutrition, () => _open('/record/food')),
              _SymptomCard(dashboard.symptom, () => _open('/record/symptom')),
              _InjectionCard(
                  dashboard.injection, () => _open('/record/injection')),
            ] else if (state.mode == DashboardViewMode.loading) ...[
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (state.mode == DashboardViewMode.error) ...[
              Text(state.message ?? 'ホーム情報の取得中にエラーが発生しました。'),
              FilledButton(
                key: const Key('retryDashboardButton'),
                onPressed: () => ref
                    .read(dashboardControllerProvider.notifier)
                    .load(state.date),
                child: const Text('再読み込み'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(DateTime current) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: current,
    );
    if (selected != null && mounted) {
      await ref.read(dashboardControllerProvider.notifier).load(selected);
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) {
      await ref.read(dashboardControllerProvider.notifier).refresh();
    }
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard(this.section, this.open);
  final DashboardWeightSection section;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => _SectionCard(
        title: '体重',
        category: AppCategory.weight,
        actionKey: const Key('dashboardWeightAction'),
        action: section.record == null ? '記録する' : '記録を見る',
        open: open,
        children: [
          if (section.record case final record?)
            Text('${_number(record.weightKg)} kg')
          else
            const Text('未記録'),
        ],
      );
}

class _NutritionCard extends StatelessWidget {
  const _NutritionCard(this.section, this.open);
  final DashboardNutritionSection section;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final record = section.record;
    return _SectionCard(
      title: '食事',
      category: AppCategory.food,
      actionKey: const Key('dashboardFoodAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('未記録')
        else if (record.mode == DashboardNutritionMode.freeDay) ...[
          const Text('Free Day'),
          const Text('この日は栄養計算を行わない日として記録されています。'),
        ] else ...[
          Text('${record.totalCalories} kcal'),
          Text('たんぱく質 ${_number(record.totalProteinG!)} g'),
        ],
      ],
    );
  }
}

class _SymptomCard extends StatelessWidget {
  const _SymptomCard(this.section, this.open);
  final DashboardSymptomSection section;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final record = section.record;
    return _SectionCard(
      title: '体調',
      category: AppCategory.symptom,
      actionKey: const Key('dashboardSymptomAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('未記録')
        else ...[
          Text(
            '${TimeOfDay.fromDateTime(record.recordedAt.toLocal()).format(context)} 記録済み',
          ),
        ],
      ],
    );
  }
}

class _InjectionCard extends StatelessWidget {
  const _InjectionCard(this.section, this.open);
  final DashboardInjectionSection section;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final record = section.record;
    return _SectionCard(
      title: '注射',
      category: AppCategory.injection,
      actionKey: const Key('dashboardInjectionAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('未記録')
        else
          Text('${_naturalDate(record.recordDate)} 記録済み'),
      ],
    );
  }
}

class _NextInjection extends StatelessWidget {
  const _NextInjection(this.date, this.dashboardDate);

  final DateTime? date;
  final DateTime dashboardDate;

  @override
  Widget build(BuildContext context) {
    final next = date;
    final days = next == null
        ? null
        : DateUtils.dateOnly(next)
            .difference(DateUtils.dateOnly(dashboardDate))
            .inDays;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppCategory.injection.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        const CategoryIcon(AppCategory.injection),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('次回の注射',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              if (next == null)
                const Text('予定はありません')
              else
                Text(
                  _naturalDate(next),
                  key: const Key('dashboardNextInjectionDate'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
              if (days != null && days >= 0)
                Text(days == 0 ? '今日' : 'あと$days日'),
              if (next != null) const Text('実際の投与日は医療者の指示に従ってください。'),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.category,
    required this.actionKey,
    required this.action,
    required this.open,
    required this.children,
  });
  final String title;
  final AppCategory category;
  final Key actionKey;
  final String action;
  final VoidCallback open;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: CategoryIcon(category),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
          trailing:
              TextButton(key: actionKey, onPressed: open, child: Text(action)),
        ),
        const Divider(),
      ]);
}

String _naturalDate(DateTime date) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${date.month}月${date.day}日（${weekdays[date.weekday - 1]}）';
}

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
