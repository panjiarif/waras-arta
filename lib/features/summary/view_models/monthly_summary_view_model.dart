import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/finance.dart';

final yearlySummaryProvider = StreamProvider.autoDispose
    .family<YearlySummarySnapshot, int>((ref, year) {
      return ref.watch(financeRepositoryProvider).watchYearlySummary(year);
    });
