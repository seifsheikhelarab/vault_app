import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import 'day_grouping.dart';

/// Rising slab (28px crown) holding the capture form.
Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const CaptureSheet(),
  );
}

/// Blocks anything that is not a valid in-progress money string: digits and
/// at most one decimal point with at most two decimals. Invalid edits
/// (paste of `"12.345"`, a second dot, letters) are dropped wholesale.
class _MoneyInputFormatter extends TextInputFormatter {
  static final _inProgress = RegExp(r'^\d{0,9}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _inProgress.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key});

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  String? _categoryId;
  String? _amountError;
  bool _saving = false;

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
      await repo.create(
        amountMinor: amountMinor,
        categoryId: _categoryId,
        occurredAt: _date,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense saved — it will sync when online.')),
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
              'Log an expense',
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
              inputFormatters: [_MoneyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'EGP ',
                errorText: _amountError,
              ),
            ),
            _CategoryPicker(
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
                  : const Text('Save expense'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uncategorized plus one chip per local category.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesListProvider).value ?? const <CategoryRow>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Uncategorized'),
          selected: selectedId == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final category in categories)
          ChoiceChip(
            label: Text(category.name),
            selected: selectedId == category.id,
            onSelected: (_) => onChanged(category.id),
          ),
      ],
    );
  }
}
