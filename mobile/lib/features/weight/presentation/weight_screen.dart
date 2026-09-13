import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/weight.dart';
import '../providers/weight_provider.dart';
import '../../../shared/presentation/category_icon.dart';

class WeightScreen extends ConsumerStatefulWidget {
  const WeightScreen({super.key});
  @override
  ConsumerState<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends ConsumerState<WeightScreen> {
  final weight = TextEditingController(), memo = TextEditingController();
  String? validation;
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(weightControllerProvider.notifier).load(DateTime.now()));
  }

  @override
  void dispose() {
    weight.dispose();
    memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weightControllerProvider);
    final edit = state.mode == WeightMode.edit;
    ref.listen<int>(
      weightControllerProvider.select((value) => value.formRevision),
      (_, __) {
        final current = ref.read(weightControllerProvider);
        weight.text = current.record?.weightKg.toString() ?? '';
        memo.text = current.record?.memo ?? '';
        validation = null;
      },
    );
    return Scaffold(
        appBar: AppBar(
            title: CategoryTitle(AppCategory.weight, edit ? '体重を編集' : '体重を記録')),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(children: [
              ListTile(
                  title: const Text('日付'),
                  subtitle: Text(
                      '${state.date.year}/${state.date.month.toString().padLeft(2, '0')}/${state.date.day.toString().padLeft(2, '0')}'),
                  onTap: state.busy
                      ? null
                      : () async {
                          final d = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              initialDate: state.date);
                          if (d != null) {
                            ref.read(weightControllerProvider.notifier).load(d);
                          }
                        }),
              TextField(
                  key: const Key('weightField'),
                  controller: weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration:
                      const InputDecoration(labelText: '体重', suffixText: 'kg')),
              TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final t = await showTimePicker(
                              context: context,
                              initialTime:
                                  TimeOfDay.fromDateTime(state.recordedAt));
                          if (t != null) {
                            ref
                                .read(weightControllerProvider.notifier)
                                .setRecordedAt(DateTime(
                                    state.date.year,
                                    state.date.month,
                                    state.date.day,
                                    t.hour,
                                    t.minute));
                          }
                        },
                  child: Text(
                      '記録時刻 ${TimeOfDay.fromDateTime(state.recordedAt).format(context)}')),
              TextField(
                  controller: memo,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'メモ（任意）')),
              if (validation != null)
                Text(validation!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (state.message != null) Text(state.message!),
              FilledButton(
                  onPressed: state.busy ||
                          state.mode == WeightMode.loading ||
                          state.mode == WeightMode.error
                      ? null
                      : () async {
                          setState(() => validation = null);
                          try {
                            final ok = await ref
                                .read(weightControllerProvider.notifier)
                                .save(weight.text, memo.text, state.recordedAt);
                            if (ok) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          edit ? '体重を更新しました。' : '体重を保存しました。')));
                            }
                          } on WeightValidationException catch (e) {
                            setState(() => validation = e.message);
                          }
                        },
                  child: Text(state.busy
                      ? '処理中…'
                      : edit
                          ? '更新する'
                          : '保存する')),
              if (edit)
                TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: state.busy
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                        title: const Text('この体重記録を削除しますか？'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('キャンセル')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('削除'))
                                        ]));
                            if (yes == true) {
                              await ref
                                  .read(weightControllerProvider.notifier)
                                  .delete();
                            }
                          },
                    child: const Text('記録を削除')),
            ])));
  }
}
