import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/symptom.dart';
import '../providers/symptom_provider.dart';
import '../../../shared/presentation/category_icon.dart';

class SymptomScreen extends ConsumerStatefulWidget {
  const SymptomScreen({super.key});
  @override
  ConsumerState<SymptomScreen> createState() => _SymptomScreenState();
}

class _SymptomScreenState extends ConsumerState<SymptomScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(symptomControllerProvider.notifier).load(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(symptomControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const CategoryTitle(AppCategory.symptom, '体調記録')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('日付'),
          subtitle: Text(_dateLabel(state.date)),
          onTap: state.busy
              ? null
              : () async {
                  final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: state.date);
                  if (date != null) {
                    ref.read(symptomControllerProvider.notifier).load(date);
                  }
                },
        ),
        if (state.viewMode == SymptomViewMode.loading)
          const Center(child: CircularProgressIndicator())
        else if (state.viewMode == SymptomViewMode.error) ...[
          Text(state.message ?? '体調記録の処理中にエラーが発生しました。'),
          FilledButton(
              onPressed: () =>
                  ref.read(symptomControllerProvider.notifier).load(state.date),
              child: const Text('再読み込み')),
        ] else ...[
          FilledButton(
              key: const Key('addSymptomButton'),
              onPressed: state.busy ? null : () => _openForm(state.date),
              child: const Text('体調を記録')),
          if (state.records.isEmpty)
            const Text('この日の体調記録はまだありません。', key: Key('emptySymptomState')),
          for (final record in state.records)
            ListTile(
              key: Key('symptom-${record.id}'),
              title: Text(TimeOfDay.fromDateTime(record.recordedAt.toLocal())
                  .format(context)),
              subtitle: Text(
                  '吐き気 ${record.nausea}  腹痛 ${record.abdominalPain}\nだるさ ${record.fatigue}  食欲 ${record.appetite}${record.bowelCondition == null ? '' : '\n便通 ${record.bowelCondition!.label}'}'),
              isThreeLine: true,
              onTap: state.busy ? null : () => _openForm(state.date, record),
            ),
          if (state.busy) const Text('処理中…', key: Key('symptomBusy')),
          if (state.message != null)
            Text(state.message!, key: const Key('symptomMessage')),
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text('強い症状や気になる変化がある場合は、医療機関へ相談してください。'),
          ),
        ],
      ]),
    );
  }

  Future<void> _openForm(DateTime date, [SymptomRecord? record]) async {
    final result = await showDialog<SymptomFormResult>(
        context: context,
        builder: (_) => SymptomFormDialog(date: date, record: record));
    if (result == null || !mounted) return;
    final controller = ref.read(symptomControllerProvider.notifier);
    final success = result.deleteRequested
        ? await controller.delete(record!.id)
        : record == null
            ? await controller.create(result.values!.requestFor(date))
            : await controller.update(
                record.id, result.values!.requestFor(date));
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.deleteRequested
              ? '体調記録を削除しました。'
              : record == null
                  ? '体調記録を保存しました。'
                  : '体調記録を更新しました。')));
    }
  }
}

class SymptomFormResult {
  const SymptomFormResult.save(this.values) : deleteRequested = false;
  const SymptomFormResult.delete()
      : values = null,
        deleteRequested = true;
  final SymptomFormValues? values;
  final bool deleteRequested;
}

class SymptomFormDialog extends StatefulWidget {
  const SymptomFormDialog({super.key, required this.date, this.record});
  final DateTime date;
  final SymptomRecord? record;
  @override
  State<SymptomFormDialog> createState() => _SymptomFormDialogState();
}

class _SymptomFormDialogState extends State<SymptomFormDialog> {
  late DateTime recordedAt;
  late int nausea, abdominalPain, fatigue, appetite;
  late BowelCondition? bowel;
  late final TextEditingController memo;
  String? validation;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordedAt = record?.recordedAt.toLocal() ?? DateTime.now();
    nausea = record?.nausea ?? 1;
    abdominalPain = record?.abdominalPain ?? 1;
    fatigue = record?.fatigue ?? 1;
    appetite = record?.appetite ?? 1;
    bowel = record?.bowelCondition;
    memo = TextEditingController(text: record?.memo ?? '');
  }

  @override
  void dispose() {
    memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.record != null;
    return AlertDialog(
      title: Text(edit ? '体調を編集' : '体調を記録'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            key: const Key('symptomTimeButton'),
            onPressed: () async {
              final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(recordedAt));
              if (time != null) {
                setState(() => recordedAt = DateTime(
                    widget.date.year,
                    widget.date.month,
                    widget.date.day,
                    time.hour,
                    time.minute));
              }
            },
            child: Text(
                '時刻 ${TimeOfDay.fromDateTime(recordedAt).format(context)}'),
          ),
          _ScaleInput(
              label: '吐き気',
              value: nausea,
              onChanged: (value) => setState(() => nausea = value)),
          _ScaleInput(
              label: '腹痛',
              value: abdominalPain,
              onChanged: (value) => setState(() => abdominalPain = value)),
          _ScaleInput(
              label: 'だるさ',
              value: fatigue,
              onChanged: (value) => setState(() => fatigue = value)),
          _ScaleInput(
              label: '食欲',
              value: appetite,
              onChanged: (value) => setState(() => appetite = value)),
          DropdownButtonFormField<BowelCondition?>(
            key: const Key('bowelField'),
            initialValue: bowel,
            decoration: const InputDecoration(labelText: '便通'),
            items: [
              const DropdownMenuItem(value: null, child: Text('記録しない')),
              for (final condition in BowelCondition.values)
                DropdownMenuItem(
                    value: condition, child: Text(condition.label)),
            ],
            onChanged: (value) => setState(() => bowel = value),
          ),
          TextField(
            key: const Key('symptomMemoField'),
            controller: memo,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'メモ（任意）'),
          ),
          if (validation != null)
            Text(validation!, key: const Key('symptomValidation')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        if (edit)
          TextButton(
              key: const Key('deleteSymptomButton'),
              onPressed: _confirmDelete,
              child: const Text('記録を削除')),
        FilledButton(
            key: const Key('saveSymptomButton'),
            onPressed: _save,
            child: Text(edit ? '更新' : '保存')),
      ],
    );
  }

  void _save() {
    final values = SymptomFormValues(
        recordedAt: recordedAt,
        nausea: nausea,
        abdominalPain: abdominalPain,
        fatigue: fatigue,
        appetite: appetite,
        bowelCondition: bowel,
        memo: memo.text);
    try {
      values.requestFor(widget.date);
      Navigator.pop(context, SymptomFormResult.save(values));
    } on SymptomValidationException catch (error) {
      setState(() => validation = error.message);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('この体調記録を削除しますか？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('削除')),
              ],
            ));
    if (confirmed == true && mounted) {
      Navigator.pop(context, const SymptomFormResult.delete());
    }
  }
}

class _ScaleInput extends StatelessWidget {
  const _ScaleInput(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label 1から10',
        child: Column(children: [
          Text('$label $value'),
          Slider(
              key: Key('scale-$label'),
              min: 1,
              max: 10,
              divisions: 9,
              value: value.toDouble(),
              label: value.toString(),
              onChanged: (next) => onChanged(next.round())),
        ]),
      );
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
