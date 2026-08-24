import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/session_controller.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/budgets/budget_editor_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/expenses/expenses_screen.dart';
import '../../features/recurring/recurring_editor_screen.dart';
import '../../features/recurring/recurring_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/home_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/sign-in',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      // Boot still deciding (stored cookie being validated): hold course so a
      // cold-start deep link is not rewritten before the gate knows the answer.
      if (session.isLoading) return null;

      final loc = state.matchedLocation;
      final onAuth = loc == '/sign-in' || loc == '/sign-up';
      final authed = session.value ?? false;

      if (!authed) {
        if (onAuth) return null;
        // Carry the original destination; restored after sign-in.
        return '/sign-in?from=${Uri.encodeQueryComponent(state.uri.toString())}';
      }
      if (onAuth) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/')) ? from : '/home';
      }
      return null;
    },
    routes: [
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
      GoRoute(
        path: '/reports',
        builder: (_, _) => const ReportsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
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
                path: '/chat',
                builder: (_, _) => const ChatScreen(),
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
