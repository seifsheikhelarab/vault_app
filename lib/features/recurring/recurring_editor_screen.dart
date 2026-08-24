import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/network/api_client.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/ui/offline_banner.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/recurring_repository.dart';
import '../expenses/day_grouping.dart';
import 'recurring_providers.dart';

/// Create/edit a single recurring rule. `ruleId == 'new'` is create mode.
/// Everything except reading the form is gated on connectivity: rules are
/// not synced offline, so saves/deletes refuse outright with a reason.
class RecurringEditorScreen extends ConsumerStatefulWidget {
  const RecurringEditorScreen({required this.ruleId, super.key});

  final String ruleId;

  @override
  ConsumerState<RecurringEditorScreen> createState() =>
      _RecurringEditorScreenState();
}

class _RecurringEditorScreenState extends ConsumerState<RecurringEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '1');
  String? _categoryId;
  String _frequency = 'monthly';
  DateTime _anchorDate = DateTime.now();
  bool _paused = false;
  bool _saving = false;
  bool _seeded = false;

  bool get _isNew => widget.ruleId == 'new';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final categories =
        ref.watch(categoriesListProvider).value ?? const [];
    RecurringRow? existing;
    for (final r
        in ref.watch(recurringListProvider).value ?? const <RecurringRow>[]) {
      if (r.id == widget.ruleId) existing = r;
    }

    // Seed once when editing and the cached row arrives.
    if (!_isNew && !_seeded && existing != null) {
      _seeded = true;
      _nameCtrl.text = existing.name;
      _amountCtrl.text = formatPiasters(existing.amountMinor);
      _intervalCtrl.text = '${existing.interval}';
      _categoryId = existing.categoryId;
      _frequency = existing.frequency;
      _anchorDate = existing.anchorDate;
      _paused = existing.paused;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New rule' : 'Edit rule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            if (!online) ...[
              OfflineBanner(
                message:
                    'Rule changes need a connection — rules are never synced offline.',
                rounded: true,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameCtrl,
              enabled: online,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) {
                final name = (v ?? '').trim();
                if (name.isEmpty) return 'Enter a name';
                if (name.length > 100) return 'Use at most 100 characters';
                return null;
              },
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
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Daily')),
                ButtonSegment(value: 'weekly', label: Text('Weekly')),
                ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ],
              selected: {_frequency},
              onSelectionChanged: online
                  ? (s) => setState(() => _frequency = s.first)
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _intervalCtrl,
              enabled: online,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration:
                  const InputDecoration(labelText: 'Every N (1–1000)'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n < 1 || n > 1000) {
                  return 'Enter a number from 1 to 1000';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: online ? _pickAnchorDate : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Anchor date'),
                child: Text(formatFullDate(_anchorDate)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final c in categories)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged:
                  online ? (v) => setState(() => _categoryId = v) : null,
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Paused'),
                subtitle: const Text('Paused rules skip their next runs.'),
                value: _paused,
                onChanged:
                    online ? (v) => setState(() => _paused = v) : null,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: online && !_saving ? () => _save(online) : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isNew ? 'Create rule' : 'Save changes'),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: online && !_saving ? _delete : null,
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Delete rule'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _anchorDate = picked);
  }

  Future<void> _save(bool online) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final amount = parsePiasters(_amountCtrl.text);
      // ponytail: server PATCH documents no null-clear for categoryId, so
      // "None" on an edit omits the field and keeps the prior category;
      // revisit when the contract confirms nullability.
      final repo = await ref.read(recurringRepositoryProvider.future);
      if (_isNew) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          amountMinor: amount,
          frequency: _frequency,
          anchorDate: _anchorDate,
          interval: int.parse(_intervalCtrl.text.trim()),
          categoryId: _categoryId,
          online: online,
        );
      } else {
        await repo.update(
          widget.ruleId,
          name: _nameCtrl.text.trim(),
          amountMinor: amount,
          frequency: _frequency,
          anchorDate: _anchorDate,
          interval: int.parse(_intervalCtrl.text.trim()),
          categoryId: _categoryId,
          paused: _paused,
          online: online,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isNew ? 'Rule created.' : 'Rule saved.')));
        context.pop();
      }
    } on RecurringOfflineException {
      _snack('Rule changes need a connection — nothing was saved.');
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
        title: const Text('Delete rule?'),
        content: const Text(
            'This removes the rule for good. Expenses it already logged are kept.'),
        actions: [
          TextButton(
              onPressed: () => context.pop(false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => context.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(recurringRepositoryProvider.future);
      await repo.delete(widget.ruleId,
          online: ref.read(isOnlineProvider));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rule deleted.')));
        context.pop();
      }
    } on RecurringOfflineException {
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
