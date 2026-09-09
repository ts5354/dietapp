import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('設定')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
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
        bottomNavigationBar: NavigationBar(
          selectedIndex: 3,
          onDestinationSelected: (index) {
            if (index == 0) context.go('/');
            if (index == 1) context.go('/record');
            if (index == 2) context.go('/history');
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.add_circle_outline), label: 'Record'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(
                icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            ...children,
          ],
        ),
      );
}
