import 'package:flutter/material.dart';

import '../../core/ui/empty_state.dart';

/// Placeholder until the reports ticket ships real charts. Honest per
/// DESIGN.md: names what arrives, never fakes it.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'Charts are coming',
        message:
            'Spending breakdowns and trends over time land here with the reports release.',
      ),
    );
  }
}
