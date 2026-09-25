import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/finance.dart';

typedef YearlySummaryQuery = ({int year, AccountBalanceGroup? balanceGroup});

final yearlySummaryProvider = StreamProvider.autoDispose
    .family<YearlySummarySnapshot, YearlySummaryQuery>((ref, query) {
      return ref
          .watch(financeRepositoryProvider)
          .watchYearlySummary(query.year, balanceGroup: query.balanceGroup);
    });
