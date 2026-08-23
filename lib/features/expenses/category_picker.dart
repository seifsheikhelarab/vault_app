import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Uncategorized plus one chip per local category.
class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

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
