import 'package:flutter/material.dart';

import '../../core/ui/empty_state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.calendar_view_month_outlined,
          title: 'Your month at a glance',
          message:
              'Totals and budgets land here once expenses exist. Capture starts with the ember button.',
        ),
      ),
    );
  }
}
