import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  test('overview chart snapshot owns immutable lists and totals expenses', () {
    final expenses = <DailyExpenseTotal>[
      DailyExpenseTotal(day: DateTime(2025, 1, 1), expense: 125),
      DailyExpenseTotal(day: DateTime(2025, 1, 2), expense: 75),
    ];
    final balances = <PrimaryBalancePoint>[
      PrimaryBalancePoint(
        day: DateTime(2024, 12, 31),
        balance: -50,
        isCurrent: false,
      ),
      PrimaryBalancePoint(
        day: DateTime(2025, 1, 2),
        balance: 100,
        isCurrent: true,
      ),
    ];

    final snapshot = OverviewChartsSnapshot(
      today: DateTime(2025, 1, 2),
      dailyExpenses: expenses,
      balancePoints: balances,
    );
    expenses.clear();
    balances.clear();

    expect(snapshot.dailyExpenses, hasLength(2));
    expect(snapshot.balancePoints, hasLength(2));
    expect(snapshot.totalExpense, 200);
    expect(() => snapshot.dailyExpenses.clear(), throwsUnsupportedError);
    expect(() => snapshot.balancePoints.clear(), throwsUnsupportedError);
  });
}
