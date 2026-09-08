import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/injection.dart';
import '../providers/injection_provider.dart';

class InjectionScreen extends ConsumerStatefulWidget {
  const InjectionScreen({super.key});
  @override
  ConsumerState<InjectionScreen> createState() => _InjectionScreenState();
}

class _InjectionScreenState extends ConsumerState<InjectionScreen> {
  final dose = TextEditingController();
  final memo = TextEditingController();
  InjectionSite? site;
  String? validation;

  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(injectionControllerProvider.notifier).load(DateTime.now()));
  }

  @override
  void dispose() {
    dose.dispose();
    memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(injectionControllerProvider);
    final edit = state.mode == InjectionMode.edit;
    ref.listen<int>(
      injectionControllerProvider.select((value) => value.formRevision),
      (_, __) {
        final current = ref.read(injectionControllerProvider);
        dose.text =
            current.record == null ? '' : formatDose(current.record!.doseMg);
        memo.text = current.record?.memo ?? '';
        setState(() {
          site = current.record?.injectionSite;
          validation = null;
        });
      },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('注射記録')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('日付'),
          subtitle: Text(_dateLabel(state.date)),
          onTap: state.busy
              ? null
              : () async {
                  final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: state.date);
                  if (selected != null) {
                    ref
                        .read(injectionControllerProvider.notifier)
                        .load(selected);
                  }
                },
        ),
        if (state.nextScheduledDate case final next?) ...[
          const Text('記録上の次回予定日'),
          Text(_dateLabel(next), key: const Key('nextInjectionDate')),
          const Text('実際の投与日は医療者の指示に従ってください。'),
          const SizedBox(height: 12),
        ],
        if (state.mode == InjectionMode.loading)
          const Center(child: CircularProgressIndicator())
        else if (state.mode == InjectionMode.error) ...[
          Text(state.message ?? '注射記録の処理中にエラーが発生しました。'),
          FilledButton(
              onPressed: () => ref
                  .read(injectionControllerProvider.notifier)
                  .load(state.date),
              child: const Text('再読み込み')),
        ] else ...[
          if (!edit) const Text('この日の注射記録はまだありません。'),
          TextButton(
            key: const Key('injectionTimeButton'),
            onPressed: state.busy
                ? null
                : () async {
                    final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(state.injectedAt));
                    if (time != null) {
                      ref
                          .read(injectionControllerProvider.notifier)
                          .setInjectedAt(DateTime(
                              state.date.year,
                              state.date.month,
                              state.date.day,
                              time.hour,
                              time.minute));
                    }
                  },
            child: Text(
                '注射時刻 ${TimeOfDay.fromDateTime(state.injectedAt).format(context)}'),
          ),
          TextField(
            key: const Key('doseField'),
            controller: dose,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            decoration: const InputDecoration(
                labelText: 'dose',
                suffixText: 'mg',
                helperText: '医療者から指示されたdoseを入力してください'),
          ),
          DropdownButtonFormField<InjectionSite>(
            key: const Key('injectionSiteField'),
            initialValue: site,
            decoration: const InputDecoration(labelText: '注射部位'),
            items: [
              for (final value in InjectionSite.values)
                DropdownMenuItem(value: value, child: Text(value.label))
            ],
            onChanged:
                state.busy ? null : (value) => setState(() => site = value),
          ),
          TextField(
              key: const Key('injectionMemoField'),
              controller: memo,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'メモ（任意）')),
          if (validation != null)
            Text(validation!, key: const Key('injectionValidation')),
          if (state.message != null)
            Text(state.message!, key: const Key('injectionMessage')),
          FilledButton(
            key: const Key('saveInjectionButton'),
            onPressed: state.busy ? null : () => _save(state, edit),
            child: Text(state.busy
                ? '処理中…'
                : edit
                    ? '更新'
                    : '保存'),
          ),
          if (edit)
            TextButton(
              key: const Key('deleteInjectionButton'),
              onPressed: state.busy ? null : _confirmDelete,
              child: const Text('記録を削除'),
            ),
          const Text('doseや実際の投与日は、医療者の指示に従ってください。'),
        ],
      ]),
    );
  }

  Future<void> _save(InjectionState state, bool edit) async {
    setState(() => validation = null);
    try {
      final success = await ref
          .read(injectionControllerProvider.notifier)
          .save(dose.text, site, memo.text, state.injectedAt, state.date);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(edit ? '注射記録を更新しました。' : '注射記録を保存しました。')));
      }
    } on InjectionValidationException catch (error) {
      setState(() => validation = error.message);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(title: const Text('この注射記録を削除しますか？'), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除')),
            ]));
    if (confirmed == true && mounted) {
      final success =
          await ref.read(injectionControllerProvider.notifier).delete();
      if (success && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('注射記録を削除しました。')));
      }
    }
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
