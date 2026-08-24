import 'package:flutter/material.dart';

import '../../core/theme/vault_theme.dart';
import 'capture_sheet.dart';

/// The ember FAB — the only hot element in the world, allowed to exist only
/// because it logs an expense. Sits above the NavigationBar on every main tab.
class CaptureFab extends StatelessWidget {
  const CaptureFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: VaultColors.ember,
      foregroundColor: Colors.white,
      tooltip: 'Log an expense',
      onPressed: () => showCaptureSheet(context),
      child: const Icon(Icons.add),
    );
  }
}
