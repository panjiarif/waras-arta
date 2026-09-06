import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/core/formatters.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('parseRupiah', () {
    test('accepts whole rupiah, surrounding whitespace, and upper bound', () {
      expect(parseRupiah('0'), 0);
      expect(parseRupiah('25000'), 25000);
      expect(parseRupiah('  25000\n'), 25000);
      expect(parseRupiah('00025'), 25);
      expect(parseRupiah('$maxAmount'), maxAmount);
    });

    test(
      'rejects ambiguous or invalid values instead of changing their sum',
      () {
        for (final input in [
          '',
          '   ',
          '25.000',
          '25,000',
          '25000.50',
          '25000,50',
          '25 000',
          '25\n000',
          '+25000',
          '-25000',
          'Rp 25000',
          '1e3',
          '0x10',
          'abc',
          '1000000000000',
          '0000000000001',
        ]) {
          expect(parseRupiah(input), isNull, reason: 'Input: "$input"');
        }
      },
    );
  });

  group('validateRupiah', () {
    test('requires a positive amount by default', () {
      expect(validateRupiah('15000'), isNull);
      expect(validateRupiah('0'), 'Nominal harus lebih besar dari nol.');
      expect(validateRupiah('000'), 'Nominal harus lebih besar dari nol.');
    });

    test('allows zero for opening balances only when requested', () {
      expect(validateRupiah('0', allowZero: true), isNull);
      expect(validateRupiah('1000', allowZero: true), isNull);
      expect(validateRupiah('-1', allowZero: true), isNotNull);
    });

    test('reports a format error for missing, decimal, or oversized input', () {
      const error =
          'Gunakan rupiah bulat, maksimal 12 digit, tanpa titik/koma.';
      for (final input in <String?>[
        null,
        '',
        '1.000',
        '1,50',
        '1000000000000',
      ]) {
        expect(validateRupiah(input), error);
      }
    });
  });

  group('saldo bertanda', () {
    test('menerima saldo positif, nol, dan negatif', () {
      expect(parseSignedRupiah('25000'), 25000);
      expect(parseSignedRupiah('0'), 0);
      expect(parseSignedRupiah('-12500'), -12500);
      expect(parseSignedRupiah('  -500\n'), -500);
      expect(validateSignedRupiah('-12500'), isNull);
    });

    test('menolak format ambigu dan nilai di luar batas', () {
      for (final input in [
        '',
        '-',
        '+100',
        '1.000',
        '-1,000',
        '1000000000000',
        '-1000000000000',
      ]) {
        expect(parseSignedRupiah(input), isNull, reason: 'Input: "$input"');
        expect(
          validateSignedRupiah(input),
          isNotNull,
          reason: 'Input: "$input"',
        );
      }
    });
  });

  test('formats whole rupiah with Indonesian thousands separators', () {
    expect(formatRupiah(0), 'Rp 0');
    expect(formatRupiah(1250000), 'Rp 1.250.000');
    expect(formatRupiah(-12500), '-Rp 12.500');
  });

  test('formats month and date in Indonesian', () {
    final date = DateTime(2024, 8, 17, 21, 30);
    expect(formatMonth(date), 'Agustus 2024');
    expect(formatDate(date), '17 Agu 2024');
  });

  test('dateOnly preserves civil date without time-of-day', () {
    final date = DateTime(2024, 2, 29, 23, 59, 58, 123);
    expect(dateOnly(date), DateTime(2024, 2, 29));
    expect(dateOnly(DateTime.utc(2024, 2, 29, 23)), DateTime(2024, 2, 29));
  });
}
