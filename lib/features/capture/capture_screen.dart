import 'package:flutter/material.dart';

import '../expenses/capture_sheet.dart';

/// The Add expense tab: the capture form as a full page, amount field
/// already focused. Saving stores locally (syncs later) and clears for the
/// next capture — logging takes as few steps as the platform allows.
class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CaptureSheet(embedded: true),
      ),
    );
  }
}
