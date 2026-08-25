import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_providers.dart';

/// Quiet one-line notice shown while the device is online but rows are
/// still owed to the server, or the last cycle failed. Never blocks
/// interaction — sync retries on its own triggers.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    if (status == null) return const SizedBox.shrink();
    if (!status.lastCycleFailed && status.pendingCount == 0) {
      return const SizedBox.shrink();
    }
    final message = status.pendingCount > 0
        ? '${status.pendingCount} change${status.pendingCount == 1 ? '' : 's'} '
            'waiting to sync'
        : 'Last sync attempt failed — retrying automatically';
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(
            status.pendingCount > 0
                ? Icons.cloud_upload_outlined
                : Icons.sync_problem_outlined,
          ),
          title: Text(message),
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
