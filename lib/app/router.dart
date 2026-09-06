import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ledger/views/account_form_screen.dart';
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
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
