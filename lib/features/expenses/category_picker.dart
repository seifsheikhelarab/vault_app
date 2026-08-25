import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/paint.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Uncategorized plus one chip per local category, each wearing its
/// paint-pot dab so a category reads as one color everywhere.
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
    final scheme = Theme.of(context).colorScheme;
    // The chip IS the paint pot: whole card wears the category tone. Light
    // pots take white lettering, the paler night pots take ink.
    final onTone = scheme.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF141A19);

    ChoiceChip uncategorized = ChoiceChip(
      label: const Text('Uncategorized'),
      selected: selectedId == null,
      onSelected: (_) => onChanged(null),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        uncategorized,
        for (final category in categories)
          ChoiceChip(
            avatar: selectedId == category.id
                ? Icon(Icons.check, size: 16, color: onTone)
                : null,
            label: Text(
              category.name,
              style: TextStyle(color: onTone, fontWeight: FontWeight.w600),
            ),
            selected: selectedId == category.id,
            onSelected: (_) => onChanged(category.id),
            backgroundColor: categoryTone(category.id, scheme),
            selectedColor: categoryTone(category.id, scheme),
            side: selectedId == category.id
                ? BorderSide(color: onTone, width: 1.4)
                : BorderSide.none,
          ),
      ],
    );
  }
}
