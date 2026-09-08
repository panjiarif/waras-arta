import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../domain/finance.dart';
import '../features/backup/views/backup_screen.dart';
import '../features/budgets/views/budget_detail_screen.dart';
import '../features/budgets/views/budget_form_screen.dart';
import '../features/budgets/views/budget_list_screen.dart';
import '../features/categories/views/category_form_screen.dart';
import '../features/categories/views/category_list_screen.dart';
import '../features/ledger/views/account_adjustment_screen.dart';
import '../features/ledger/views/account_detail_screen.dart';
import '../features/ledger/views/account_edit_screen.dart';
import '../features/ledger/views/account_form_screen.dart';
import '../features/ledger/views/entry_detail_screen.dart';
import '../features/ledger/views/entry_form_screen.dart';
import '../features/ledger/views/home_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'backup',
            builder: (context, state) => const BackupScreen(),
          ),
          GoRoute(
            path: 'budgets',
            builder: (context, state) => const BudgetListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const BudgetFormScreen(),
              ),
              GoRoute(
                path: ':budgetId',
                builder: (context, state) => BudgetDetailScreen(
                  budgetId:
                      int.tryParse(state.pathParameters['budgetId'] ?? '') ??
                      -1,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => BudgetEditScreen(
                      budgetId:
                          int.tryParse(
                            state.pathParameters['budgetId'] ?? '',
                          ) ??
                          -1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'accounts/new',
            builder: (context, state) => const AccountFormScreen(),
          ),
          GoRoute(
            path: 'accounts/:accountId',
            builder: (context, state) => AccountDetailScreen(
              accountId:
                  int.tryParse(state.pathParameters['accountId'] ?? '') ?? -1,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => AccountEditScreen(
                  accountId:
                      int.tryParse(state.pathParameters['accountId'] ?? '') ??
                      -1,
                ),
              ),
              GoRoute(
                path: 'adjust',
                builder: (context, state) => AccountBalanceAdjustmentScreen(
                  accountId:
                      int.tryParse(state.pathParameters['accountId'] ?? '') ??
                      -1,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'transactions/new',
            builder: (context, state) => EntryFormScreen(
              initialDate: parseTransactionDateQuery(
                state.uri.queryParameters['date'],
              ),
            ),
          ),
          GoRoute(
            path: 'categories',
            builder: (context, state) => CategoryListScreen(
              initialKind: state.uri.queryParameters.containsKey('kind')
                  ? _categoryKind(state)
                  : null,
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    CategoryGroupFormScreen(initialKind: _categoryKind(state)),
              ),
              GoRoute(
                path: ':parentId/children/new',
                builder: (context, state) => CategorySubcategoryFormScreen(
                  parentId:
                      int.tryParse(state.pathParameters['parentId'] ?? '') ??
                      -1,
                  kind: _categoryKind(state),
                ),
              ),
              GoRoute(
                path: ':categoryId/edit',
                builder: (context, state) => CategoryEditScreen(
                  categoryId:
                      int.tryParse(state.pathParameters['categoryId'] ?? '') ??
                      -1,
                  kind: _categoryKind(state),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'transactions/:entryId',
            builder: (context, state) => EntryDetailScreen(
              entryId:
                  int.tryParse(state.pathParameters['entryId'] ?? '') ?? -1,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => EntryEditScreen(
                  entryId:
                      int.tryParse(state.pathParameters['entryId'] ?? '') ?? -1,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

CategoryKind _categoryKind(GoRouterState state) =>
    state.uri.queryParameters['kind'] == CategoryKind.income.name
    ? CategoryKind.income
    : CategoryKind.expense;

DateTime? parseTransactionDateQuery(String? value, {DateTime? today}) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('-').map(int.parse).toList(growable: false);
  final result = DateTime(parts[0], parts[1], parts[2]);
  if (result.year != parts[0] ||
      result.month != parts[1] ||
      result.day != parts[2]) {
    return null;
  }
  final lastDay = dateOnly(today ?? DateTime.now());
  if (result.isBefore(DateTime(2000)) || result.isAfter(lastDay)) return null;
  return result;
}
