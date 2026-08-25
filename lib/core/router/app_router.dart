import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/session_controller.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/budgets/budget_editor_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/capture/capture_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/expenses/expenses_screen.dart';
import '../../features/recurring/recurring_editor_screen.dart';
import '../../features/recurring/recurring_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/home_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      // Boot still deciding: park on the splash so a cold start never
      // flashes sign-in before the gate knows the answer.
      if (session.isLoading) return null;

      final loc = state.matchedLocation;
      final onAuth = loc == '/sign-in' || loc == '/sign-up';
      final authed = session.value ?? false;

      if (loc == '/boot') return authed ? '/log' : '/sign-in';

      if (!authed) {
        if (onAuth) return null;
        // Carry the original destination; restored after sign-in.
        return '/sign-in?from=${Uri.encodeQueryComponent(state.uri.toString())}';
      }
      if (onAuth) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/')) ? from : '/log';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/boot',
        builder: (_, _) => const _BootScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (_, _) => const SignUpScreen(),
      ),
      // Budget management lives outside the tab shell (full-screen push).
      // 'new' is create mode; any other segment is a budget id.
      GoRoute(
        path: '/budgets',
        builder: (_, _) => const BudgetsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                BudgetEditorScreen(budgetId: state.pathParameters['id']!),
          ),
        ],
      ),
      // Recurring rules mirror budgets: online-only CRUD, full-screen push.
      GoRoute(
        path: '/recurring',
        builder: (_, _) => const RecurringScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                RecurringEditorScreen(ruleId: state.pathParameters['id']!),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          // Capture first: opening Vault lands on the log-an-expense form.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/log',
                builder: (_, _) => const CaptureScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/expenses',
                builder: (_, _) => const ExpensesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Shown only while the session gate is still resolving on cold start.
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Vault', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
