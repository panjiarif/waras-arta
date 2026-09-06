import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
