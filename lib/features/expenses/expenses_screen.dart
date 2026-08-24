import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/ui/empty_state.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_providers.dart';
import 'categories_sheet.dart';
import 'capture_sheet.dart';
import 'day_grouping.dart';

const _pageSize = 30;

/// One paged local query: newest-first, optionally category-filtered.
class ExpensesPageQuery {
  const ExpensesPageQuery({this.categoryId, required this.limit});

  final String? categoryId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is ExpensesPageQuery &&
      other.categoryId == categoryId &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(categoryId, limit);
}

final _expensePageProvider = StreamProvider.autoDispose
    .family<List<ExpenseRow>, ExpensesPageQuery>((ref, query) {
  final repo = ref.watch(expensesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchPage(categoryId: query.categoryId, limit: query.limit);
});



/// Newest-first, day-grouped history with per-day totals, category filter
/// chips, and purely-local infinite scroll.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _filterCategoryId;
  int _limit = _pageSize;
  List<ExpenseRow> _lastRows = const [];

  void _selectFilter(String? categoryId) {
    setState(() {
      _filterCategoryId = categoryId;
      _limit = _pageSize;
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // A full page means more may exist locally; grow the window.
    if (notification.metrics.extentAfter < 600 && _lastRows.length >= _limit) {
      setState(() => _limit += _pageSize);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Expenses',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Manage categories',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: () => showCategoriesSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _FilterChips(
            selectedId: _filterCategoryId,
            onSelected: _selectFilter,
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final query =
        ExpensesPageQuery(categoryId: _filterCategoryId, limit: _limit);
    final page = ref.watch(_expensePageProvider(query));

    // Keep prior content visible while a grown limit or switched filter
    // reloads, so infinite scroll never blanks the list.
    List<ExpenseRow> rows;
    if (page.hasValue) {
      rows = page.requireValue;
    } else if (page.isLoading && _lastRows.isNotEmpty) {
      rows = _lastRows;
    } else if (page.hasError) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load expenses',
        message: 'Something went wrong reading your local history.',
      );
    } else {
      rows = const [];
    }
    _lastRows = rows;

    if (rows.isEmpty) {
      final filtered = _filterCategoryId != null;
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title:
            filtered ? 'Nothing in this category' : 'Nothing logged yet',
        message: filtered
            ? 'No expenses match this filter yet.'
            : 'Everything you log lands here, online or off, newest first.',
      );
    }

    final groups = groupByDay(rows);
    final categoryNames = {
      for (final c in ref.watch(categoriesListProvider).value ?? const <CategoryRow>[])
        c.id: c.name,
    };

    return RefreshIndicator(
      onRefresh: () async =>
          (await ref.read(syncSchedulerProvider.future)).refresh(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          itemCount: groups.length,
          itemBuilder: (_, index) => _DaySection(
            group: groups[index],
            categoryNames: categoryNames,
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesListProvider).value ?? const <CategoryRow>[];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selectedId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.name),
                selected: selectedId == category.id,
                onSelected: (_) => onSelected(category.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.group, required this.categoryNames});

  final ExpenseDayGroup group;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatDayHeader(group.day),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                formatEgp(group.totalMinor),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        for (final row in group.rows)
          _ExpenseTile(row: row, categoryNames: categoryNames),
      ],
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.row, required this.categoryNames});

  final ExpenseRow row;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    final note = row.note;
    final title = (note != null && note.isNotEmpty)
        ? note
        : (categoryNames[row.categoryId] ?? 'Uncategorized');
    final subtitle = (note != null && note.isNotEmpty)
        ? (categoryNames[row.categoryId] ??
            (row.categoryId == null ? null : 'Uncategorized'))
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      onTap: () => showCaptureSheet(context, expense: row),
      title: Row(
        children: [
          Flexible(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // Sourced-from-recurring marker (recurringDefinitionId arrived via
          // sync). Neutral derived color: ember is capture-only and teal
          // never shrinks to trim, so the badge abstains from both.
          if (row.recurringId != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Logged by a recurring rule',
              child: Icon(
                Icons.autorenew,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Text(
        formatEgp(row.amountMinor),
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
