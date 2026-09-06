import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/finance.dart';
import '../features/categories/views/category_form_screen.dart';
import '../features/categories/views/category_list_screen.dart';
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
            path: 'accounts/new',
            builder: (context, state) => const AccountFormScreen(),
          ),
          GoRoute(
            path: 'transactions/new',
            builder: (context, state) => const EntryFormScreen(),
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
