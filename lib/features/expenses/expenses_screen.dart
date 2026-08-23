import 'package:flutter/material.dart';

import '../../core/ui/empty_state.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Nothing logged yet',
          message:
              'Everything you log lands here, online or off, newest first.',
        ),
      ),
    );
  }
}
