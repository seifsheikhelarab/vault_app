import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/api_base_url.dart';
import 'core/router/app_router.dart';
import 'core/theme/vault_theme.dart';
import 'data/sync/sync_providers.dart';

void main() async {
  // Release builds must not ship pointing at localhost or over http.
  ensureApiBaseUrlValid(isRelease: kReleaseMode);

  // A widget build crash renders a quiet placeholder instead of the red/grey
  // error grid.
  ErrorWidget.builder = (details) => const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF14181F),
          child: Center(child: Text('Something went wrong.')),
        ),
      );

  // Keep errors observable in the console at least.
  _installFallbackErrorHooks();
  runApp(const ProviderScope(child: VaultApp()));
}

void _installFallbackErrorHooks() {
  // Uncaught async errors would otherwise vanish in release builds; report
  // them through FlutterError so one hook sees all.
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'platform dispatcher',
    ));
    return true;
  };
}

class VaultApp extends ConsumerWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiates the sync trigger listeners (session-resolved,
    // connectivity regain) for the app's lifetime.
    ref.watch(syncSchedulerProvider);
    return MaterialApp.router(
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: buildVaultTheme(Brightness.light),
      darkTheme: buildVaultTheme(Brightness.dark),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
