import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/nutrition.dart';
import '../providers/nutrition_provider.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(nutritionControllerProvider.notifier).load(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nutritionControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('食事記録')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('日付'),
            subtitle: Text(_displayDate(state.date)),
            onTap: state.busy
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: state.date,
                    );
                    if (date != null) {
                      ref.read(nutritionControllerProvider.notifier).load(date);
                    }
                  },
          ),
          if (state.viewMode == NutritionViewMode.loading)
            const Center(child: CircularProgressIndicator())
          else if (state.viewMode == NutritionViewMode.error)
            _ErrorContent(
              message: state.message ?? '食事記録の処理中にエラーが発生しました。',
              retry: () => ref
                  .read(nutritionControllerProvider.notifier)
                  .load(state.date),
            )
          else if (state.day case final day?)
            ..._readyContent(context, state, day),
        ],
      ),
    );
  }

  List<Widget> _readyContent(
      BuildContext context, NutritionState state, NutritionDay day) {
    return [
      if (day.mode == NutritionMode.unrecorded) ...[
        const Text('まだ食事記録がありません', key: Key('unrecordedState')),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('addFoodButton'),
          onPressed: state.busy ? null : () => _openFoodForm(context, day),
          child: const Text('食事を記録'),
        ),
        OutlinedButton(
          key: const Key('freeDayButton'),
          onPressed: state.busy ? null : () => _confirmFreeDay(context),
          child: const Text('Free Dayとして記録'),
        ),
      ] else if (day.mode == NutritionMode.freeDay) ...[
        const Text('Free Day',
            key: Key('freeDayState'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('この日は栄養計算をしない日として記録されています。'),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('normalModeButton'),
          onPressed:
              state.busy ? null : () => _changeMode(NutritionMode.normal),
          child: const Text('通常の記録に戻す'),
        ),
      ] else ...[
        const Text('記録合計',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text('${day.totalCalories} kcal', key: const Key('calorieTotal')),
        Text('${formatNutritionNumber(day.totalProteinG!)} g protein',
            key: const Key('proteinTotal')),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('addFoodButton'),
          onPressed: state.busy ? null : () => _openFoodForm(context, day),
          child: const Text('食事を記録'),
        ),
        OutlinedButton(
          key: const Key('freeDayButton'),
          onPressed: state.busy
              ? null
              : () => day.foods.isEmpty
                  ? _confirmFreeDay(context)
                  : _showFoodBlocksFreeDay(context),
          child: const Text('Free Dayとして記録'),
        ),
        if (day.foods.isEmpty) const Text('食事記録はまだありません。'),
        for (final food in day.foods)
          ListTile(
            key: Key('food-${food.id}'),
            title: Text(food.name),
            subtitle: Text(
                '${TimeOfDay.fromDateTime(food.eatenAt.toLocal()).format(context)}  ${food.calories} kcal  ${formatNutritionNumber(food.proteinG)} g'),
            onTap: state.busy ? null : () => _openFoodForm(context, day, food),
          ),
      ],
      if (state.busy)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('処理中…', key: Key('nutritionBusy')),
        ),
      if (state.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(state.message!, key: const Key('nutritionMessage')),
        ),
    ];
  }

  Future<void> _openFoodForm(BuildContext context, NutritionDay day,
      [FoodLog? food]) async {
    if (day.mode == NutritionMode.freeDay) return;
    final result = await showDialog<FoodFormResult>(
      context: context,
      builder: (_) => FoodFormDialog(food: food, selectedDate: day.date),
    );
    if (result == null || !mounted) return;
    final controller = ref.read(nutritionControllerProvider.notifier);
    bool success;
    if (result.deleteRequested) {
      success = await controller.deleteFood(food!.id);
    } else {
      final request = result.values!.requestFor(day.date);
      success = food == null
          ? await controller.createFood(request)
          : await controller.updateFood(food.id, request);
    }
    if (success && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
          content: Text(result.deleteRequested
              ? '食事記録を削除しました。'
              : food == null
                  ? '食事記録を保存しました。'
                  : '食事記録を更新しました。')));
    }
  }

  Future<void> _confirmFreeDay(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Free Dayとして記録しますか？'),
        content: const Text('この日は栄養計算をしない日として記録されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Free Dayにする')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _changeMode(NutritionMode.freeDay);
    }
  }

  Future<void> _changeMode(NutritionMode mode) async {
    final success =
        await ref.read(nutritionControllerProvider.notifier).setMode(mode);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mode == NutritionMode.freeDay
              ? 'Free Dayとして記録しました。'
              : '通常の記録に戻しました。')));
    }
  }

  Future<void> _showFoodBlocksFreeDay(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content:
              const Text('この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる')),
          ],
        ),
      );
}

class FoodFormResult {
  const FoodFormResult.save(this.values) : deleteRequested = false;
  const FoodFormResult.delete()
      : values = null,
        deleteRequested = true;
  final FoodFormValues? values;
  final bool deleteRequested;
}

class FoodFormDialog extends StatefulWidget {
  const FoodFormDialog({super.key, required this.selectedDate, this.food});
  final DateTime selectedDate;
  final FoodLog? food;

  @override
  State<FoodFormDialog> createState() => _FoodFormDialogState();
}

class _FoodFormDialogState extends State<FoodFormDialog> {
  late final TextEditingController name;
  late final TextEditingController calories;
  late final TextEditingController protein;
  late final TextEditingController memo;
  late DateTime time;
  String? validation;

  @override
  void initState() {
    super.initState();
    final food = widget.food;
    name = TextEditingController(text: food?.name ?? '');
    calories = TextEditingController(text: food?.calories.toString() ?? '');
    protein = TextEditingController(
        text: food == null ? '' : formatNutritionNumber(food.proteinG));
    memo = TextEditingController(text: food?.memo ?? '');
    time = food?.eatenAt.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    name.dispose();
    calories.dispose();
    protein.dispose();
    memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.food != null;
    return AlertDialog(
      title: Text(edit ? '食事を編集' : '食事を記録'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('foodNameField'),
            controller: name,
            decoration: const InputDecoration(labelText: '名前'),
          ),
          TextField(
            key: const Key('caloriesField'),
            controller: calories,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration:
                const InputDecoration(labelText: 'カロリー', suffixText: 'kcal'),
          ),
          TextField(
            key: const Key('proteinField'),
            controller: protein,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            decoration:
                const InputDecoration(labelText: 'たんぱく質', suffixText: 'g'),
          ),
          TextButton(
            key: const Key('foodTimeButton'),
            onPressed: () async {
              final selected = await showTimePicker(
                  context: context, initialTime: TimeOfDay.fromDateTime(time));
              if (selected != null) {
                setState(() => time = DateTime(
                    widget.selectedDate.year,
                    widget.selectedDate.month,
                    widget.selectedDate.day,
                    selected.hour,
                    selected.minute));
              }
            },
            child: Text('時刻 ${TimeOfDay.fromDateTime(time).format(context)}'),
          ),
          TextField(
            key: const Key('foodMemoField'),
            controller: memo,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'メモ（任意）'),
          ),
          if (validation != null)
            Text(validation!,
                key: const Key('foodValidation'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        if (edit)
          TextButton(
            key: const Key('deleteFoodButton'),
            onPressed: _confirmDelete,
            child: const Text('記録を削除'),
          ),
        FilledButton(
          key: const Key('saveFoodButton'),
          onPressed: _submit,
          child: Text(edit ? '更新' : '保存'),
        ),
      ],
    );
  }

  void _submit() {
    final values = FoodFormValues(
      name: name.text,
      calories: calories.text,
      protein: protein.text,
      time: time,
      memo: memo.text,
    );
    try {
      values.requestFor(widget.selectedDate);
      Navigator.pop(context, FoodFormResult.save(values));
    } on FoodValidationException catch (error) {
      setState(() => validation = error.message);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この食事記録を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const FoodFormResult.delete());
    }
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(message),
        FilledButton(onPressed: retry, child: const Text('再読み込み')),
      ]);
}

String _displayDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
