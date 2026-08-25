import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/offline_banner.dart';
import '../../data/providers.dart';
import 'budget_providers.dart';

/// Budget management surface. Reads come from the local cache (stale-safe);
/// the pull-to-refresh and every write are gated on connectivity.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final cached = ref.watch(budgetsListProvider);
    final online = ref.watch(isOnlineProvider);
    final categories = ref.watch(categoriesListProvider).value ?? const [];
    final names = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New budget',
            onPressed: () => context.push('/budgets/new'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online)
            const OfflineBanner(
              message:
                  'Showing saved budgets. Creating or editing needs a connection — budgets are not synced offline.',
            ),
          Expanded(
            child: cached.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load budgets',
                message: 'Pull to try again.',
              ),
              data: (_) {
                if (progress.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _refresh(context, ref),
                    child: ListView(
                      children: const [
                        SizedBox(height: 160),
                        EmptyState(
                          icon: Icons.savings_outlined,
                          title: 'No budgets yet',
                          message:
                              'Create a budget to track spending against a weekly or monthly cap.',
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _refresh(context, ref),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: progress.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = progress[i];
                      final label =
                          names[p.budget.categoryId] ?? 'Overall budget';
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: InkWell(
                          onTap: () => context.push('/budgets/${p.budget.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(
                                      '${p.budget.periodType == 'week' ? 'Weekly' : 'Monthly'} · ${formatEgp(p.limitMinor)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(value: p.ratio),
                                const SizedBox(height: 6),
                                Text(
                                  p.over
                                      ? '${formatEgp(p.spent)} spent — over cap by ${formatEgp(p.spent - p.limitMinor)}'
                                      : '${formatEgp(p.spent)} of ${formatEgp(p.limitMinor)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: p.over
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : Theme.of(context)
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

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final online = ref.read(isOnlineProvider);
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("You're offline — showing the last synced budgets."),
      ));
      return;
    }
    try {
      final repo = await ref.read(budgetsRepositoryProvider.future);
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
