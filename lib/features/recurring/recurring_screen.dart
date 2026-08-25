import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/offline_banner.dart';
import '../../data/providers.dart';
import '../expenses/day_grouping.dart';
import 'recurring_providers.dart';

/// Recurring-rule management surface. Reads come from the local cache
/// (stale-safe); the pull-to-refresh and every write are gated on
/// connectivity — rules are never synced offline.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringListProvider);
    final online = ref.watch(isOnlineProvider);
    final categories = ref.watch(categoriesListProvider).value ?? const [];
    final names = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New rule',
            onPressed: () => context.push('/recurring/new'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online)
            const OfflineBanner(
              message:
                  'Showing saved rules. Creating or editing needs a connection — rules are not synced offline.',
            ),
          Expanded(
            child: rules.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load rules',
                message: 'Pull to try again.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _refresh(context, ref),
                    child: ListView(
                      children: const [
                        SizedBox(height: 160),
                        EmptyState(
                          icon: Icons.autorenew_outlined,
                          title: 'No recurring payments yet',
                          message:
                              'Create a payment and the server logs the expense for you on schedule.',
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _refresh(context, ref),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: InkWell(
                          onTap: () => context.push('/recurring/${r.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(
                                      formatEgp(r.amountMinor),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    _frequencyLabel(r.frequency, r.interval),
                                    names[r.categoryId] ?? 'Uncategorized',
                                  ].join(' · '),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r.paused
                                      ? 'Paused'
                                      : 'Next: ${formatDayHeader(r.nextRunAt.toLocal())}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _frequencyLabel(String frequency, int interval) {
    const named = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
    };
    if (interval == 1) return named[frequency] ?? frequency;
    const unit = {'daily': 'day', 'weekly': 'week', 'monthly': 'month'};
    return 'Every $interval ${unit[frequency] ?? frequency}s';
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final online = ref.read(isOnlineProvider);
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("You're offline — showing the last fetched rules."),
      ));
      return;
    }
    try {
      final repo = await ref.read(recurringRepositoryProvider.future);
      await repo.refresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Refresh failed — check your connection.'),
        ));
      }
    }
  }
}
