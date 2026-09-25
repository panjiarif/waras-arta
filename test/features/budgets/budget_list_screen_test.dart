import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/providers.dart';
import 'package:waras_arta/domain/budget.dart';
import 'package:waras_arta/features/budgets/views/budget_list_screen.dart';
import 'package:waras_arta/features/calendar/view_models/calendar_view_model.dart';

import 'fake_budget_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpList(
    WidgetTester tester,
    FakeBudgetRepository repository, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          budgetRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(DateTime(2026, 2, 10)),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: const Scaffold(body: BudgetListScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String keyedText(WidgetTester tester, String key) {
    return tester.widget<Text>(find.byKey(Key(key))).data!;
  }

  testWidgets('summary totals two active items in the current filter', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 1000000,
          spentAmount: 250000,
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 3000000,
          spentAmount: 750000,
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository);

    expect(find.byKey(const Key('budget-list-summary')), findsOneWidget);
    expect(keyedText(tester, 'budget-list-summary-spent'), 'Rp 1.000.000');
    expect(keyedText(tester, 'budget-list-summary-limit'), 'Rp 4.000.000');
    expect(
      tester
          .getSemantics(find.byKey(const Key('budget-list-summary-semantics')))
          .label,
      'Total anggaran yang tampil, 2 anggaran, 1 rentang periode, '
      'Februari 2026, '
      'terpakai Rp 1.000.000 dari batas Rp 4.000.000, 25 persen.',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('budget-list-summary-progress')),
          )
          .value,
      .25,
    );
    semanticsHandle.dispose();
  });

  testWidgets('mixed-range note and totals follow the selected kind filter', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 1000000,
          spentAmount: 250000,
          period: BudgetPeriod.monthly(2026, 2),
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 1000000,
          spentAmount: 750000,
          period: BudgetPeriod.yearly(2026),
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository);

    expect(
      find.text(
        'Mencakup 2 rentang berbeda. Total ini hanya gabungan hasil filter, '
        'bukan sisa satu periode.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('budget-list-summary-progress')), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const Key('budget-list-summary-semantics')))
          .label,
      'Total anggaran yang tampil, 2 anggaran, 2 rentang periode, '
      'terpakai Rp 1.000.000 dari batas Rp 2.000.000. '
      'Mencakup 2 rentang berbeda. Total ini hanya gabungan hasil filter, '
      'bukan sisa satu periode.',
    );

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-monthly')));
    await tester.pumpAndSettle();

    expect(keyedText(tester, 'budget-list-summary-spent'), 'Rp 250.000');
    expect(keyedText(tester, 'budget-list-summary-limit'), 'Rp 1.000.000');
    expect(
      find.text(
        'Mencakup 2 rentang berbeda. Total ini hanya gabungan hasil filter, '
        'bukan sisa satu periode.',
      ),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('budget-list-summary-semantics')))
          .label,
      'Total anggaran yang tampil, 1 anggaran, 1 rentang periode, '
      'Februari 2026, '
      'terpakai Rp 250.000 dari batas Rp 1.000.000, 25 persen.',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('budget-list-summary-progress')),
          )
          .value,
      .25,
    );

    await tester.tap(find.byKey(const Key('budget-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('budget-kind-custom')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget-list-summary')), findsNothing);
    expect(find.byKey(const Key('budget-empty-title')), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets('empty result omits every summary element', (tester) async {
    await pumpList(tester, FakeBudgetRepository());

    expect(find.byKey(const Key('budget-list-summary')), findsNothing);
    expect(
      find.byKey(const Key('budget-list-summary-semantics')),
      findsNothing,
    );
    expect(find.byKey(const Key('budget-list-summary-spent')), findsNothing);
    expect(find.byKey(const Key('budget-list-summary-limit')), findsNothing);
    expect(find.byKey(const Key('budget-empty-title')), findsOneWidget);
  });

  testWidgets('exceeded summary exposes actual usage without clamping', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          limitAmount: 1000000,
          spentAmount: 1250000,
          categories: [fakeBudgetCategory(id: 11)],
        ),
      ],
    );

    await pumpList(tester, repository);

    expect(keyedText(tester, 'budget-list-summary-spent'), 'Rp 1.250.000');
    expect(keyedText(tester, 'budget-list-summary-limit'), 'Rp 1.000.000');
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('budget-list-summary-progress')),
          )
          .value,
      1,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('budget-list-summary-semantics')))
          .label,
      'Total anggaran yang tampil, 1 anggaran, 1 rentang periode, '
      'Februari 2026, '
      'terpakai Rp 1.250.000 dari batas Rp 1.000.000, 125 persen.',
    );
    semanticsHandle.dispose();
  });

  testWidgets('summary fits 320 pixels at 200 percent with full semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeBudgetRepository(
      items: [
        fakeBudgetProgress(
          id: 1,
          limitAmount: 999999999999,
          spentAmount: 999999999999,
          categories: [fakeBudgetCategory(id: 11)],
        ),
        fakeBudgetProgress(
          id: 2,
          limitAmount: 999999999999,
          spentAmount: 999999999999,
          categories: [fakeBudgetCategory(id: 12)],
        ),
      ],
    );

    await pumpList(tester, repository, textScaler: const TextScaler.linear(2));

    expect(find.byKey(const Key('budget-list-summary')), findsOneWidget);
    expect(
      keyedText(tester, 'budget-list-summary-spent'),
      'Rp 1.999.999.999.998',
    );
    expect(
      keyedText(tester, 'budget-list-summary-limit'),
      'Rp 1.999.999.999.998',
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('budget-list-summary-semantics')))
          .label,
      'Total anggaran yang tampil, 2 anggaran, 1 rentang periode, '
      'Februari 2026, '
      'terpakai Rp 1.999.999.999.998 dari batas Rp 1.999.999.999.998, '
      '100 persen.',
    );
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });
}
