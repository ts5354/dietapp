import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/domain/dashboard.dart';
import '../features/dashboard/providers/dashboard_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(dashboardControllerProvider.notifier).load(DateTime.now()));
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
              title: const Text('日付'),
              subtitle: Text(_dateLabel(state.date)),
              onTap: state.mode == DashboardViewMode.loading
                  ? null
                  : () => _selectDate(state.date),
            ),
            if (state.mode == DashboardViewMode.loading) ...[
              const Center(child: CircularProgressIndicator()),
              _RecordLinks(open: _open),
            ] else if (state.mode == DashboardViewMode.error) ...[
              Text(state.message ?? 'ホーム情報の取得中にエラーが発生しました。'),
              FilledButton(
                key: const Key('retryDashboardButton'),
                onPressed:
                    ref.read(dashboardControllerProvider.notifier).refresh,
                child: const Text('再読み込み'),
              ),
              _RecordLinks(open: _open),
            ] else if (state.dashboard case final dashboard?) ...[
              _WeightCard(dashboard.weight, () => _open('/record/weight')),
              _NutritionCard(dashboard.nutrition, () => _open('/record/food')),
              _SymptomCard(dashboard.symptom, () => _open('/record/symptom')),
              _InjectionCard(
                  dashboard.injection, () => _open('/record/injection')),
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

class _RecordLinks extends StatelessWidget {
  const _RecordLinks({required this.open});
  final Future<void> Function(String path) open;
  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('記録する'),
        FilledButton(
            onPressed: () => open('/record/weight'), child: const Text('体重')),
        FilledButton(
            onPressed: () => open('/record/food'), child: const Text('食事')),
        FilledButton(
            onPressed: () => open('/record/symptom'), child: const Text('体調')),
        FilledButton(
            onPressed: () => open('/record/injection'),
            child: const Text('注射')),
      ]);
}

class _WeightCard extends StatelessWidget {
  const _WeightCard(this.section, this.open);
  final DashboardWeightSection section;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => _SectionCard(
        title: '体重',
        actionKey: const Key('dashboardWeightAction'),
        action: section.record == null ? '記録する' : '記録を見る',
        open: open,
        children: [
          if (section.record case final record?)
            Text('${_number(record.weightKg)} kg')
          else
            const Text('この日の記録はありません。'),
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
      actionKey: const Key('dashboardFoodAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('この日の記録はありません。')
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
      actionKey: const Key('dashboardSymptomAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('この日の記録はありません。')
        else ...[
          Text(TimeOfDay.fromDateTime(record.recordedAt.toLocal())
              .format(context)),
          Text('吐き気 ${record.nausea} / 腹痛 ${record.abdominalPain}'),
          Text('だるさ ${record.fatigue} / 食欲 ${record.appetite}'),
          if (record.bowelCondition case final bowel?)
            Text('便通 ${_bowelLabel(bowel)}'),
          const Text('強い症状や気になる変化がある場合は、医療機関へ相談してください。'),
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
      actionKey: const Key('dashboardInjectionAction'),
      action: record == null ? '記録する' : '記録を見る',
      open: open,
      children: [
        if (record == null)
          const Text('この日の記録はありません。')
        else
          Text('最新の記録日 ${_dateLabel(record.recordDate)}'),
        if (section.nextScheduledDate case final next?) ...[
          const Text('記録上の次回予定日'),
          Text(_dateLabel(next), key: const Key('dashboardNextInjectionDate')),
          const Text('実際の投与日は医療者の指示に従ってください。'),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.actionKey,
    required this.action,
    required this.open,
    required this.children,
  });
  final String title;
  final Key actionKey;
  final String action;
  final VoidCallback open;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              ...children,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    key: actionKey, onPressed: open, child: Text(action)),
              ),
            ],
          ),
        ),
      );
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

String _bowelLabel(DashboardBowelCondition value) => switch (value) {
      DashboardBowelCondition.normal => '通常',
      DashboardBowelCondition.constipation => '便秘',
      DashboardBowelCondition.diarrhea => '下痢',
      DashboardBowelCondition.other => 'その他',
    };
