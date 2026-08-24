import 'package:flutter/material.dart';

/// Shared offline notice: why the surface is stale and what needs a
/// connection. [rounded] gives editors an inset card; list screens use the
/// full-width default.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.message, this.rounded = false, super.key});

  final String message;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final banner = Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: rounded ? BorderRadius.circular(12) : null,
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: const Text(
          "You're offline",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(message),
        dense: true,
      ),
    );
    return rounded ? banner : Column(children: [banner]);
  }
}
