import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/domain/dashboard.dart';
import '../features/dashboard/providers/dashboard_provider.dart';
import '../core/theme/app_theme.dart';
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
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: state.mode == DashboardViewMode.loading
                  ? null
                  : () => _selectDate(state.date),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _naturalDate(state.date),
                      key: const Key('dashboardDate'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF24332F),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 20),
                ]),
              ),
            ),
            const SizedBox(height: 16),
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
                () => _open('/record/injection'),
              ),
              const SizedBox(height: 24),
              Text('今日の記録', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(children: [
                  _WeightCard(
                    dashboard.weight,
                    dashboard.date,
                    () => _open('/record/weight'),
                  ),
                  _NutritionCard(
                      dashboard.nutrition, () => _open('/record/food')),
                  _SymptomCard(
                      dashboard.symptom, () => _open('/record/symptom')),
                  _InjectionCard(
                      dashboard.injection, () => _open('/record/injection')),
                ]),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('homeRecordButton'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: () => context.go('/record'),
                child: const Row(children: [
                  Icon(Icons.add_circle_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('記録する',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.chevron_right),
                ]),
              ),
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
  const _WeightCard(this.section, this.dashboardDate, this.open);
  final DashboardWeightSection section;
  final DateTime dashboardDate;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final record = section.record;
    final recordForDay = record != null &&
            record.recordDate.year == dashboardDate.year &&
            record.recordDate.month == dashboardDate.month &&
            record.recordDate.day == dashboardDate.day
        ? record
        : null;
    return _SectionCard(
      title: '体重',
      category: AppCategory.weight,
      actionKey: const Key('dashboardWeightAction'),
      action: recordForDay == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (recordForDay != null)
          Text('${_number(recordForDay.weightKg)} kg')
        else
          const Text('この日の記録はありません'),
      ],
    );
  }
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
          const Text('この日の記録はありません')
        else if (record.mode == DashboardNutritionMode.freeDay) ...[
          const Text('Free Day'),
          const Text('この日は栄養計算を行わない日として記録されています。'),
        ] else ...[
          Text('${_integer(record.totalCalories!)} kcal / '
              '${_number(record.totalProteinG!)} g'),
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
          const Text('この日の記録はありません')
        else ...[
          Text(
            '${TimeOfDay.fromDateTime(record.recordedAt.toLocal()).format(context)} に記録済み',
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
        if (record == null) const Text('この日の記録はありません') else const Text('記録済み'),
      ],
    );
  }
}

class _NextInjection extends StatelessWidget {
  const _NextInjection(this.date, this.dashboardDate, this.open);

  final DateTime? date;
  final DateTime dashboardDate;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final next = date;
    final days = next == null
        ? null
        : DateUtils.dateOnly(next)
            .difference(DateUtils.dateOnly(dashboardDate))
            .inDays;
    return Material(
      color: AppColors.mint.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('nextInjectionCard'),
        borderRadius: BorderRadius.circular(24),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const CategoryIcon(AppCategory.injection),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('次回の注射', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 3),
                  if (next == null)
                    const Text('予定はありません')
                  else
                    Text(
                      _naturalDate(next),
                      key: const Key('dashboardNextInjectionDate'),
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700),
                    ),
                  if (days != null && days >= 0) ...[
                    const SizedBox(height: 7),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Text(days == 0 ? '今日' : 'あと$days日'),
                      ),
                    ),
                  ],
                  if (next != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      '実際の投与日は医療者の指示に従ってください。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.mint),
          ]),
        ),
      ),
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
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              key: actionKey,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mint,
                backgroundColor: AppColors.mint.withValues(alpha: 0.1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: open,
              child: Text(action),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18),
          ]),
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

String _integer(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',');
}
