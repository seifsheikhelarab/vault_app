import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.autorenew_outlined),
            title: const Text('Recurring rules'),
            trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            onTap: () => context.push('/recurring'),
          ),
          ListTile(
            title: const Text('Version'),
            trailing: Text(
              'pre-release',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            title: Text(
              'Sign out',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
