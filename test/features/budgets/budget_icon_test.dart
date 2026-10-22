import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/core/category_icons.dart';
import 'package:waras_arta/features/budgets/views/budget_widgets.dart';

import 'fake_budget_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final key in <String?>[null, 'home', 'bolt']) {
    testWidgets('list and detail use effective budget icon $key', (
      tester,
    ) async {
      final progress = fakeBudgetProgress(
        iconKey: key,
        categories: [
          fakeBudgetCategory(),
          fakeBudgetCategory(id: 12, iconKey: 'directions_car'),
        ],
      );
      final expected = categoryIconFor(key ?? 'category');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  BudgetCompactRow(progress: progress, onTap: () {}),
                  BudgetProgressCard(progress: progress),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Icon>(find.byKey(const ValueKey('budget-icon-1'))).icon,
        expected,
      );
      expect(
        tester.widget<Icon>(find.byKey(const Key('budget-detail-icon'))).icon,
        expected,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
