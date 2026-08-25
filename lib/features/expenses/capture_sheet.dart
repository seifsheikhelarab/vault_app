import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/ui/money_input_formatter.dart';
import '../../core/ui/paint.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import 'category_picker.dart';
import 'day_grouping.dart';
import '../recurring/recurring_editor_screen.dart';

/// Rising slab (28px crown) holding the capture form. Pass [expense] to edit
/// an existing row instead: same sheet, prefilled, with a delete action.
///
/// Pass [embedded] when the form lives as a full tab (Add expense): saving
/// then clears the form for the next capture instead of closing the sheet.
Future<void> showCaptureSheet(BuildContext context, {ExpenseRow? expense}) {
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
  const CaptureSheet({this.expense, this.embedded = false, super.key});

  final ExpenseRow? expense;

  /// Full-tab mode: after a save the form resets instead of popping, and the
  /// amount field takes focus immediately.
  final bool embedded;

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
  bool get _embedded => widget.embedded;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    if (e == null) {
      _amountController = TextEditingController();
      _noteController = TextEditingController();
      _date = DateTime.now();
    } else {
      _amountController = TextEditingController(
        text: formatPiasters(e.amountMinor),
      );
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
      if (_embedded && e == null) {
        // Tab capture: clear for the next expense instead of navigating.
        _amountController.clear();
        _noteController.clear();
        setState(() {
          _date = DateTime.now();
          _categoryId = null;
          _saving = false;
        });
      } else {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing == null
                ? 'Expense saved'
                : 'Expense updated',
          ),
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
          'It is removed here and on the server the next time Vault syncs.',
        ),
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
          content: Text('Expense deleted'),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Creating on the tab: the amount lives on the committed teal wall —
    // the app's opening grammar, flexed to fill the viewport. Editing in
    // the sheet: ink digits on plaster.
    final onWall = _embedded && _editing == null;

    /// The amount monument. `filled: false` is load-bearing: the theme's
    /// inputDecorationTheme fills every field, which would paint a near-
    /// white box over the wall and drown the white digits.
    Widget amountField() => TextField(
      controller: _amountController,
      autofocus: _embedded && _editing == null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [MoneyInputFormatter()],
      textAlign: TextAlign.center,
      cursorColor: onWall ? Colors.white : VaultColors.ember,
      style: TextStyle(
        fontFamily: vaultDisplayFamily,
        fontSize: 64,
        height: 1.15,
        letterSpacing: -0.5,
        color: onWall ? Colors.white : scheme.onSurface,
      ),
      decoration: InputDecoration(
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: '0',
        hintStyle: TextStyle(
          fontFamily: vaultDisplayFamily,
          fontSize: 64,
          letterSpacing: -0.5,
          color: onWall
              ? Colors.white.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
    );

    /// Category rail, date, note — the plaster body beneath the seam.
    Widget bodyFields() => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RegistrationLabel('Category'),
          const SizedBox(height: 8),
          // One calm rail, never a ragged wall of chips.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: CategoryPicker(
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _pickDate,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child: Text(formatFullDate(_date)),
              ),
            ],
          ),
          TextFormField(
            controller: _noteController,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              counterText: '',
            ),
          ),
        ],
      ),
    );

    Widget errorLine() => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Text(
        _amountError!,
        style: TextStyle(color: scheme.error),
        textAlign: TextAlign.center,
      ),
    );

    final saveButton = Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: FilledButton(
        // Ember law: creating an expense is the capture action.
        style: _editing == null
            ? FilledButton.styleFrom(
                backgroundColor: VaultColors.ember,
                foregroundColor: Colors.white,
              )
            : null,
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_editing == null ? 'Save expense' : 'Save changes'),
      ),
    );

    if (_embedded) {
      // Tab layout: auth's 2:3 grammar, live. The teal wall and the plaster
      // body share the viewport (5:4); the keyboard squeezes both, the body
      // scrolls, the ember action stays pinned to the thumb. No SafeArea —
      // the wall runs edge-to-edge behind the status bar, so the wall's own
      // padding clears the inset.
      final topInset = MediaQuery.paddingOf(context).top;
      return Column(
        children: [
          Flexible(
            flex: 5,
            child: ScoredPanel(
              color: VaultColors.fieldSeed,
              // Straight header edge — no diagonal on the capture wall.
              slope: 0,
              seamColor: Colors.transparent,
              padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'EGP',
                    style: chalkLabel(Colors.white.withValues(alpha: 0.85)),
                  ),
                  amountField(),
                ],
              ),
            ),
          ),
          if (_amountError != null) errorLine(),
          Flexible(flex: 4, child: SingleChildScrollView(child: bodyFields())),
          saveButton,
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: _saving ? null : _openRecurring,
              icon: const Icon(Icons.autorenew_outlined, size: 18),
              label: const Text('Make it a recurring payment'),
            ),
          ),
          const SafeArea(top: false, child: SizedBox(height: 8)),
        ],
      );
    }

    // Sheet layout (edit mode): one scrollable column, keyboard inset manual.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                'Edit expense',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            amountField(),
            if (_amountError != null) errorLine(),
            bodyFields(),
            saveButton,
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: TextButton.icon(
                onPressed: _saving ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete expense'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Carries the typed amount and picked category into a new recurring rule
  /// instead of a one-off expense. The editor gates on connectivity itself.
  Future<void> _openRecurring() async {
    int? amountMinor;
    try {
      amountMinor = _amountController.text.trim().isEmpty
          ? null
          : parsePiasters(_amountController.text);
    } on FormatException {
      amountMinor = null;
    }
    await context.push(
      '/recurring/new',
      extra: RecurringSeed(amountMinor: amountMinor, categoryId: _categoryId),
    );
    if (mounted) setState(() {}); // pick up any category edits made there
  }
}
