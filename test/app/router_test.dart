import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/app/router.dart';

void main() {
  group('parseSummaryMonthQuery', () {
    final today = DateTime(2026, 9, 25);

    test('accepts a valid normalized month', () {
      expect(
        parseSummaryMonthQuery('2024-02', today: today),
        DateTime(2024, 2),
      );
      expect(
        parseSummaryMonthQuery('2026-09', today: today),
        DateTime(2026, 9),
      );
    });

    test('rejects malformed and normalized-overflow values', () {
      for (final value in <String?>[
        null,
        '',
        '2024-2',
        '24-02',
        '2024-00',
        '2024-13',
        '2024-02-01',
        'abcd-ef',
      ]) {
        expect(
          parseSummaryMonthQuery(value, today: today),
          isNull,
          reason: '$value must not be accepted as a month query',
        );
      }
    });

    test('rejects months outside the supported ledger range', () {
      expect(parseSummaryMonthQuery('1999-12', today: today), isNull);
      expect(parseSummaryMonthQuery('2026-10', today: today), isNull);
    });
  });
}
