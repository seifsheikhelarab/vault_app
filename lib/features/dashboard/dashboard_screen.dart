import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/empty_state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(
              child: EmptyState(
                icon: Icons.calendar_view_month_outlined,
                title: 'Your month at a glance',
                message:
                    'Totals and budgets land here once expenses exist. Capture starts with the ember button.',
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push('/budgets'),
              icon: const Icon(Icons.savings_outlined),
              label: const Text('Manage budgets'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
