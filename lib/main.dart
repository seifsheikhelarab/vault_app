import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/vault_theme.dart';

void main() {
  runApp(const ProviderScope(child: VaultApp()));
}

class VaultApp extends ConsumerWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: buildVaultTheme(Brightness.light),
      darkTheme: buildVaultTheme(Brightness.dark),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
