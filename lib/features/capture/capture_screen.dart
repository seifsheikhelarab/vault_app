import 'package:flutter/material.dart';

import '../expenses/capture_sheet.dart';

/// The Add expense tab: a committed teal wall carrying the monumental
/// amount, plaster body beneath the seam. Saving stores locally (syncs
/// later) and clears for the next capture — logging takes as few steps as
/// the platform allows.
class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // No SafeArea: the painted wall runs edge-to-edge behind the status
    // bar, like the auth screens and the dashboard opening.
    return Scaffold(body: CaptureSheet(embedded: true));
  }
}
