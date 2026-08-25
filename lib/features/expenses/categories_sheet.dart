import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/empty_state.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/categories_repository.dart';

/// Local taxonomy management: create, rename, delete. Deleting keeps the
/// former expenses — they become uncategorized.
Future<void> showCategoriesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const CategoriesSheet(),
  );
}

class CategoriesSheet extends ConsumerStatefulWidget {
  const CategoriesSheet({super.key});

  @override
  ConsumerState<CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends ConsumerState<CategoriesSheet> {
  final _newNameController = TextEditingController();
  String? _addError;

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _addError = null);
    try {
      final repo = await ref.read(categoriesRepositoryProvider.future);
      await repo.create(_newNameController.text);
      _newNameController.clear();
    } on FormatException catch (e) {
      setState(() => _addError = e.message);
    } on DuplicateCategoryException {
      setState(() => _addError = 'A category with this name already exists.');
    }
  }

  Future<void> _rename(CategoryRow category) async {
    final renamed = await showDialog<bool>(
      context: context,
      builder: (_) => _RenameDialog(category: category),
    );
    if ((renamed ?? false) && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(CategoryRow category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: const Text(
          'Its expenses stay in your history — they become uncategorized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      final repo = await ref.read(categoriesRepositoryProvider.future);
      await repo.delete(category.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'Categories',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(child: _buildList()),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newNameController,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: 'New category',
                          counterText: '',
                          errorText: _addError,
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Add category',
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildList() {    final categoriesAsync = ref.watch(categoriesListProvider);
    if (categoriesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (categoriesAsync.hasError) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Categories unavailable',
        message: 'Something went wrong reading your categories.',
      );
    }
    final categories = categoriesAsync.value ?? const <CategoryRow>[];
    if (categories.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        title: 'No categories yet',
        message: 'Add one below to start sorting your expenses.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (_, index) {
        final category = categories[index];
        return ListTile(
          title: Text(category.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(category),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                onPressed: () => _delete(category),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Owns its controller so the framework disposes it only after the dialog
/// route is fully torn down — disposing on pop-start crashed the exit
/// animation (controller used after dispose).
class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.category});

  final CategoryRow category;

  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.category.name);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final repo = await ref.read(categoriesRepositoryProvider.future);
      await repo.rename(widget.category.id, _controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } on DuplicateCategoryException {
      setState(() {
        _error = 'A category with this name already exists.';
        _saving = false;
      });
    } catch (_) {
      setState(() => _saving = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename category'),
      content: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Name',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
