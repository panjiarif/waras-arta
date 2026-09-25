import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';

final overviewChartsProvider =
    StreamProvider.autoDispose<OverviewChartsSnapshot>((ref) {
      final today = dateOnly(ref.watch(currentDateProvider));
      return ref.watch(financeRepositoryProvider).watchOverviewCharts(today);
    });
