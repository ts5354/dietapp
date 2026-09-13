import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection/domain/injection.dart';
import '../../nutrition/domain/nutrition.dart';
import '../../symptom/domain/symptom.dart';
import '../../weight/domain/weight.dart';
import '../domain/history.dart';
import '../providers/history_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this)..addListener(_tabChanged);
    Future.microtask(
        () => ref.read(historyControllerProvider.notifier).loadWeight());
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (tabs.indexIsChanging) return;
    final controller = ref.read(historyControllerProvider.notifier);
    final state = ref.read(historyControllerProvider);
    if (tabs.index == 1 && state.nutrition.mode == HistoryLoadMode.loading) {
      controller.loadNutrition();
    }
    if (tabs.index == 2 && state.symptoms.mode == HistoryLoadMode.loading) {
      controller.loadSymptoms();
    }
    if (tabs.index == 3 && state.injections.mode == HistoryLoadMode.loading) {
      controller.loadInjections();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('履歴'),
            bottom: TabBar(controller: tabs, tabs: const [
              Tab(text: '体重'),
              Tab(text: '食事'),
              Tab(text: '体調'),
              Tab(text: '注射')
            ])),
        body: TabBarView(controller: tabs, children: const [
          _WeightHistory(),
          _NutritionHistory(),
          _SymptomHistory(),
          _InjectionHistory()
        ]),
      );
}

class _WeightHistory extends ConsumerWidget {
  const _WeightHistory();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyControllerProvider);
    return RefreshIndicator(
        onRefresh: () =>
            ref.read(historyControllerProvider.notifier).loadWeight(),
        child: ListView(
            key: const Key('weightHistory'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<WeightRange>(
                  segments: [
                    for (final r in WeightRange.values)
                      ButtonSegment(value: r, label: Text(r.label))
                  ],
                  selected: {
                    state.range
                  },
                  onSelectionChanged: (v) => ref
                      .read(historyControllerProvider.notifier)
                      .loadWeight(range: v.single)),
              const SizedBox(height: 16),
              _WeightBody(state.weights, state.range),
              if (state.weights.hasMore)
                TextButton(
                    key: const Key('weightLoadMore'),
                    onPressed: state.weights.loadingMore
                        ? null
                        : ref
                            .read(historyControllerProvider.notifier)
                            .loadMoreWeight,
                    child:
                        Text(state.weights.loadingMore ? '読み込み中…' : 'さらに読み込む')),
            ]));
  }
}

class _WeightBody extends StatelessWidget {
  const _WeightBody(this.state, this.range);
  final HistoryListState<WeightRecord> state;
  final WeightRange range;
  @override
  Widget build(BuildContext context) {
    if (state.mode == HistoryLoadMode.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.mode == HistoryLoadMode.error) {
      return _Error(
          message: state.message!,
          retry: () => ProviderScope.containerOf(context)
              .read(historyControllerProvider.notifier)
              .loadWeight());
    }
    if (state.items.isEmpty) return const Text('この期間の体重記録はありません。');
    final chart = oldestFirst(state.items);
    final min = chart.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b);
    final max = chart.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b);
    final axis = weightYAxis(min, max);
    final firstDate = chart.first.recordDate;
    final maxX = chart.last.recordDate.difference(firstDate).inDays.toDouble();
    return Column(children: [
      SizedBox(
          height: 220,
          child: LineChart(LineChartData(
              minX: 0,
              maxX: maxX == 0 ? 1 : maxX,
              minY: axis.min,
              maxY: axis.max,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFFE4ECE9),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                  touchSpotThreshold: 24,
                  touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((spot) {
                            final item = chart[spot.spotIndex];
                            return LineTooltipItem(
                                '${item.recordDate.month}月${item.recordDate.day}日\n${formatWeight(item.weightKg)} kg',
                                const TextStyle(color: Colors.white));
                          }).toList())),
              lineBarsData: [
                LineChartBarData(
                    spots: [
                      for (final item in chart)
                        FlSpot(
                          item.recordDate
                              .difference(firstDate)
                              .inDays
                              .toDouble(),
                          item.weightKg,
                        )
                    ],
                    color: Theme.of(context).colorScheme.primary,
                    barWidth: 3,
                    isCurved: false,
                    dotData: const FlDotData(show: true))
              ],
              titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('kg'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: axis.interval,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          interval: weightXAxisInterval(range),
                          getTitlesWidget: (value, meta) {
                            final date =
                                firstDate.add(Duration(days: value.toInt()));
                            return SideTitleWidget(
                                meta: meta,
                                child: Text('${date.month}/${date.day}'));
                          })))))),
      for (final item in state.items) ...[
        ListTile(
            title: Text('${item.recordDate.month}/${item.recordDate.day}'),
            trailing: Text('${formatWeight(item.weightKg)} kg')),
        const Divider(),
      ],
    ]);
  }
}

class _NutritionHistory extends ConsumerWidget {
  const _NutritionHistory();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _HistoryList<
          NutritionDaySummary>(
      state: ref.watch(historyControllerProvider).nutrition,
      retry: ref.read(historyControllerProvider.notifier).loadNutrition,
      loadMore: ref.read(historyControllerProvider.notifier).loadMoreNutrition,
      empty: '食事記録はありません。',
      item: (d) => ListTile(
          title: Text('${d.date.month}/${d.date.day}'),
          subtitle: Text(d.mode == NutritionMode.freeDay
              ? 'Free Day'
              : '${d.totalCalories} kcal / ${formatNutritionNumber(d.totalProteinG!)} g protein')));
}

class _SymptomHistory extends ConsumerWidget {
  const _SymptomHistory();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _HistoryList<
          SymptomRecord>(
      state: ref.watch(historyControllerProvider).symptoms,
      retry: ref.read(historyControllerProvider.notifier).loadSymptoms,
      loadMore: ref.read(historyControllerProvider.notifier).loadMoreSymptoms,
      empty: '体調記録はありません。',
      item: (s) => ListTile(
          title: Text(
              '${s.recordedAt.toLocal().month}/${s.recordedAt.toLocal().day} ${TimeOfDay.fromDateTime(s.recordedAt.toLocal()).format(context)}'),
          subtitle: Text(
              '吐き気 ${s.nausea} / 腹痛 ${s.abdominalPain} / だるさ ${s.fatigue} / 食欲 ${s.appetite}${s.bowelCondition == null ? '' : ' / 便通 ${s.bowelCondition!.label}'}')));
}

class _InjectionHistory extends ConsumerWidget {
  const _InjectionHistory();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _HistoryList<
          InjectionRecord>(
      state: ref.watch(historyControllerProvider).injections,
      retry: ref.read(historyControllerProvider.notifier).loadInjections,
      loadMore: ref.read(historyControllerProvider.notifier).loadMoreInjections,
      empty: '注射記録はありません。',
      footer: const Text('用量や実際の投与日は、医療者の指示に従ってください。'),
      item: (i) => ListTile(
          title: Text(
              '${i.recordDate.month}/${i.recordDate.day} ${TimeOfDay.fromDateTime(i.injectedAt.toLocal()).format(context)}'),
          subtitle:
              Text('${formatDose(i.doseMg)} mg / ${i.injectionSite.label}')));
}

class _HistoryList<T> extends StatelessWidget {
  const _HistoryList(
      {required this.state,
      required this.retry,
      required this.loadMore,
      required this.empty,
      required this.item,
      this.footer});
  final HistoryListState<T> state;
  final Future<void> Function() retry;
  final Future<void> Function() loadMore;
  final String empty;
  final Widget Function(T) item;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    if (state.mode == HistoryLoadMode.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.mode == HistoryLoadMode.error) {
      return _Error(message: state.message!, retry: retry);
    }
    return RefreshIndicator(
        onRefresh: retry,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (state.items.isEmpty)
                Text(empty)
              else
                for (final value in state.items) ...[
                  item(value),
                  const Divider(),
                ],
              if (state.hasMore)
                TextButton(
                    onPressed: state.loadingMore ? null : loadMore,
                    child: Text(state.loadingMore ? '読み込み中…' : 'さらに読み込む')),
              if (footer != null) footer!,
            ]));
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(message),
        FilledButton(onPressed: retry, child: const Text('再読み込み'))
      ]);
}

String formatWeight(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

double weightXAxisInterval(WeightRange range) => switch (range) {
      WeightRange.sevenDays => 1,
      WeightRange.thirtyDays => 7,
      WeightRange.threeMonths => 14,
    };

class WeightYAxis {
  const WeightYAxis(this.min, this.max, this.interval);

  final double min;
  final double max;
  final double interval;
}

WeightYAxis weightYAxis(double minimum, double maximum) {
  const interval = 2.0;
  var min = (minimum / interval).floor() * interval;
  var max = (maximum / interval).ceil() * interval;
  if (max - min < 4) {
    min -= interval;
    max += interval;
  }
  return WeightYAxis(min, max, interval);
}
