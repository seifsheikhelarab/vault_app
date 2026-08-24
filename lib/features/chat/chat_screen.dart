import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/money/money.dart';
import '../../core/network/api_client.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/theme/vault_theme.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/money_input_formatter.dart';
import '../../data/providers.dart';
import '../expenses/category_picker.dart';
import '../expenses/day_grouping.dart';

/// Chat tab: one phrase in, one editable draft out, confirm posts the
/// expense and lands back on an empty chat. Nothing about the conversation
/// persists — all state dies with this screen.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _date;
  String? _categoryId;
  String? _categoryGuess;
  String? _inlineError;
  bool _parsing = false;
  bool _saving = false;

  bool get _hasDraft => _date != null;
  bool get _busy => _parsing || _saving;

  @override
  void dispose() {
    _messageController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _inlineError = message;
      _parsing = false;
      _saving = false;
    });
  }

  String _apiErrorText(ApiException e) {
    switch (e.statusCode) {
      case 401:
        return 'Session expired — sign in again from Settings.';
      case 422:
        return "Vault couldn't read that — try rephrasing.";
      case 429:
        return 'Too many attempts — wait a minute and retry.';
      case 502:
        return 'Parsing is unavailable right now — try again.';
      default:
        return 'Something went wrong (${e.statusCode}).';
    }
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _busy) return;
    setState(() {
      _inlineError = null;
      _parsing = true;
    });
    try {
      final draft =
          await ref.read(apiClientProvider).parseExpense(message);
      if (!mounted) return;
      setState(() {
        _amountController.text = formatPiasters(draft.amountMinor);
        _noteController.text = draft.note ?? '';
        // Guess is a bare date; falls back to today on malformed input.
        _date = DateTime.tryParse(draft.occurredAtGuess) ?? DateTime.now();
        _categoryId = draft.categoryId;
        _categoryGuess = draft.categoryGuess;
        _inlineError = null;
        _parsing = false;
      });
    } on ApiException catch (e) {
      _showError(_apiErrorText(e));
    } catch (_) {
      _showError("Couldn't reach Vault — check your connection.");
    }
  }

  Future<void> _confirm() async {
    if (!_hasDraft || _busy) return;
    setState(() => _inlineError = null);

    final int amountMinor;
    try {
      amountMinor = parsePiasters(_amountController.text);
    } on FormatException catch (e) {
      setState(() => _inlineError = e.message);
      return;
    }

    setState(() => _saving = true);
    // Local midnight of the picked day, sent as a UTC instant.
    final d = _date!;
    final occurredAt = DateTime(d.year, d.month, d.day);
    final note = _noteController.text.trim();

    try {
      final id = const Uuid().v4();
      // Server first: only then does the row exist locally, already synced.
      await ref.read(apiClientProvider).createExpense(
            id: id,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            categoryId: _categoryId,
            note: note.isEmpty ? null : note,
          );
      final repo = await ref.read(expensesRepositoryProvider.future);
      await repo.createSynced(
        id: id,
        amountMinor: amountMinor,
        categoryId: _categoryId,
        occurredAt: occurredAt,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      _reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense saved.')),
      );
    } on ApiException catch (e) {
      _showError(_apiErrorText(e));
    } catch (_) {
      _showError("Couldn't reach Vault — check your connection.");
    }
  }

  /// Back to an empty chat — no history anywhere.
  void _reset() {
    setState(() {
      _messageController.clear();
      _amountController.clear();
      _noteController.clear();
      _date = null;
      _categoryId = null;
      _categoryGuess = null;
      _inlineError = null;
      _parsing = false;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(connectivityProvider).value == false;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _hasDraft
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: _buildDraftCard(context),
                    )
                  : const EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Turn words into an expense',
                      message:
                          'Type something like "taxi to airport 250" below '
                          'and Vault drafts it for you to review.',
                    ),
            ),
            if (_inlineError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  _inlineError!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            _buildComposer(context, offline),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool offline) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _messageController,
            enabled: !_busy && !_hasDraft,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => offline ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'What did you spend on?',
              counterText: '',
              suffixIcon: IconButton(
                onPressed: (_busy || offline || _hasDraft ||
                        _messageController.text.trim().isEmpty)
                    ? null
                    : _submit,
                icon: _parsing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                tooltip: 'Parse into a draft',
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.wifi_off,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You're offline — parsing needs a connection. "
                      'Use the + button to log offline instead.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offline = ref.watch(connectivityProvider).value == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review expense',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        if (_categoryGuess != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Guessed category: $_categoryGuess',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [MoneyInputFormatter()],
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Amount (EGP)',
            prefixText: 'EGP ',
          ),
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: _saving,
          child: CategoryPicker(
            selectedId: _categoryId,
            onChanged: (id) => setState(() => _categoryId = id),
          ),
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
                  Text('Date', style: Theme.of(context).textTheme.bodySmall),
                  TextButton(
                    onPressed: _saving ? null : _pickDate,
                    child: Text(formatFullDate(_date!)),
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
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),
        if (!offline)
          FilledButton(
            // Ember law: this is the capture-confirm action.
            style: FilledButton.styleFrom(
              backgroundColor: VaultColors.ember,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save expense'),
          )
        else
          Text(
            "You're offline — saving needs a connection.",
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }
}
