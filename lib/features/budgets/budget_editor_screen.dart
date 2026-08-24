import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/network/api_client.dart';
import '../../core/ui/offline_banner.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/budgets_repository.dart';
import 'budget_providers.dart';

/// Create/edit a single budget. `budgetId == 'new'` is create mode.
/// Everything except reading the form is gated on connectivity: budgets are
/// not synced offline, so saves/deletes refuse outright with a reason.
class BudgetEditorScreen extends ConsumerStatefulWidget {
  const BudgetEditorScreen({required this.budgetId, super.key});

  final String budgetId;

  @override
  ConsumerState<BudgetEditorScreen> createState() => _BudgetEditorScreenState();
}

class _BudgetEditorScreenState extends ConsumerState<BudgetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  String? _categoryId;
  String _periodType = 'month';
  bool _saving = false;
  bool _seeded = false;

  bool get _isNew => widget.budgetId == 'new';

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final categories =
        ref.watch(categoriesListProvider).value ?? const [];
    BudgetRow? existing;
    for (final b in ref.watch(budgetsListProvider).value ?? const <BudgetRow>[]) {
      if (b.id == widget.budgetId) existing = b;
    }

    // Seed once when editing and the cached row arrives.
    if (!_isNew && !_seeded && existing != null) {
      _seeded = true;
      _amountCtrl.text = formatPiasters(existing.amountMinor);
      _categoryId = existing.categoryId;
      _periodType = existing.periodType;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New budget' : 'Edit budget'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            if (!online) ...[
              OfflineBanner(
                message:
                    'Budget changes need a connection — budgets are never synced offline.',
                rounded: true,
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Overall (all spending)'),
                ),
                for (final c in categories)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged:
                  online ? (v) => setState(() => _categoryId = v) : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('Weekly')),
                ButtonSegment(value: 'month', label: Text('Monthly')),
              ],
              selected: {_periodType},
              onSelectionChanged: online
                  ? (s) => setState(() => _periodType = s.first)
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              enabled: online,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (EGP)',
                hintText: 'e.g. 2500 or 2500.50',
              ),
              validator: (v) {
                try {
                  parsePiasters(v ?? '');
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: online && !_saving ? () => _save(online) : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isNew ? 'Create budget' : 'Save changes'),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: online && !_saving ? _delete : null,
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Delete budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(bool online) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final amount = parsePiasters(_amountCtrl.text);
      final repo = await ref.read(budgetsRepositoryProvider.future);
      if (_isNew) {
        await repo.create(
          periodType: _periodType,
          amountMinor: amount,
          categoryId: _categoryId,
          online: online,
        );
      } else {
        await repo.update(
          widget.budgetId,
          periodType: _periodType,
          amountMinor: amount,
          categoryId: _categoryId,
          online: online,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_isNew ? 'Budget created.' : 'Budget saved.')));
        context.pop();
      }
    } on BudgetOfflineException {
      _snack('Budget changes need a connection — nothing was saved.');
    } on ApiException catch (e) {
      _snack(e.message ?? 'Server refused the save (${e.statusCode}).');
    } catch (_) {
      _snack('Save failed — check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
        content: const Text('This removes the budget for good. Expenses are kept.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => context.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(budgetsRepositoryProvider.future);
      await repo.delete(widget.budgetId,
          online: ref.read(isOnlineProvider));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Budget deleted.')));
        context.pop();
      }
    } on BudgetOfflineException {
      _snack('Deleting needs a connection — nothing was deleted.');
    } on ApiException catch (e) {
      _snack(e.message ?? 'Server refused the delete (${e.statusCode}).');
    } catch (_) {
      _snack('Delete failed — check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
