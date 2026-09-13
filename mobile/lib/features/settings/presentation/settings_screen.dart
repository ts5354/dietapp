import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('設定')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              _SettingsSection(
                title: '表示・単位',
                children: [
                  ListTile(
                    leading: Icon(Icons.monitor_weight_outlined),
                    title: Text('体重の単位'),
                    subtitle: Text('kg（固定）'),
                  ),
                ],
              ),
              _SettingsSection(
                title: '記録データ',
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('このアプリでは以下の記録を扱います。'),
                  ),
                  ListTile(title: Text('体重')),
                  ListTile(title: Text('食事')),
                  ListTile(title: Text('体調')),
                  ListTile(title: Text('注射')),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text('記録したデータはアプリからAPIを通じて保存されます。'),
                  ),
                ],
              ),
              _SettingsSection(
                title: '医療上の注意',
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'このアプリは記録を整理・確認するためのものです。\n'
                      '診断や治療方針、薬の量を決めるものではありません。\n\n'
                      '薬の量や投与方法については、医療者の指示に従ってください。\n'
                      '体調について心配なことがある場合は、医療者へ相談してください。',
                    ),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'アプリ情報',
                children: [ListTile(title: Text('dietapp'))],
              ),
            ],
          ),
        ),
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
            ),
            const Divider(),
            ...children,
          ],
        ),
      );
}
