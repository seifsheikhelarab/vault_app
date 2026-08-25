import 'package:flutter/material.dart';

import '../../core/ui/paint.dart';

/// Shared auth composition: the committed teal painted wall with the
/// monumental block-letter wordmark, and a plaster slab rising below,
/// joined by a scored diagonal seam. The ember accent never appears here.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: ColoredBox(
              // Literal committed field teal in both brightnesses.
              color: VaultColors.fieldSeed,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vault',
                          style: TextStyle(
                            fontFamily: vaultDisplayFamily,
                            fontSize: 64,
                            height: 1.0,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'LOG FAST. WORKS OFFLINE.',
                          style: chalkLabel(
                              Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ScoredPanel(
              color: scheme.surface,
              seamColor: scheme.primary.withValues(alpha: 0.35),
              slope: 16,
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
