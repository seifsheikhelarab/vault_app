import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/ui/money_input_formatter.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import 'category_picker.dart';
import 'day_grouping.dart';

/// Rising slab (28px crown) holding the capture form. Pass [expense] to edit
/// an existing row instead: same sheet, prefilled, with a delete action.
Future<void> showCaptureSheet(
  BuildContext context, {
  ExpenseRow? expense,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => CaptureSheet(expense: expense),
  );
}

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({this.expense, super.key});

  final ExpenseRow? expense;

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late DateTime _date;
  String? _categoryId;
  String? _amountError;
  bool _saving = false;

  ExpenseRow? get _editing => widget.expense;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    if (e == null) {
      _amountController = TextEditingController();
      _noteController = TextEditingController();
      _date = DateTime.now();
    } else {
      _amountController =
          TextEditingController(text: formatPiasters(e.amountMinor));
      _noteController = TextEditingController(text: e.note ?? '');
      _date = e.occurredAt.toLocal();
      _categoryId = e.categoryId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _amountError = null);

    final int amountMinor;
    try {
      amountMinor = parsePiasters(_amountController.text);
    } on FormatException catch (e) {
      setState(() => _amountError = e.message);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = await ref.read(expensesRepositoryProvider.future);
      final note = _noteController.text.trim();
      final e = _editing;
      if (e == null) {
        await repo.create(
          amountMinor: amountMinor,
          categoryId: _categoryId,
          occurredAt: _date,
          note: note.isEmpty ? null : note,
        );
      } else {
        await repo.update(
          id: e.id,
          amountMinor: amountMinor,
          categoryId: _categoryId,
          occurredAt: _date,
          note: note.isEmpty ? null : note,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing == null
              ? 'Expense saved — it will sync when online.'
              : 'Expense updated — it will sync when online.'),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text(
            'It is removed here and on the server the next time Vault syncs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(expensesRepositoryProvider.future);
      await repo.delete(_editing!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Expense deleted — it will sync when online.')),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing == null ? 'Log an expense' : 'Edit expense',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoneyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'EGP ',
                errorText: _amountError,
              ),
            ),
            CategoryPicker(
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.event_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date',
                          style: Theme.of(context).textTheme.bodySmall),
                      TextButton(
                        onPressed: _pickDate,
                        child: Text(formatFullDate(_date)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteController,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editing == null ? 'Save expense' : 'Save changes'),
            ),
            if (_editing != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete expense'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
