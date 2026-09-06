import 'package:intl/intl.dart';

import '../domain/finance.dart';

final _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String formatRupiah(int value) => _rupiah.format(value);
String formatMonth(DateTime date) =>
    DateFormat('MMMM yyyy', 'id_ID').format(date);
String formatDate(DateTime date) =>
    DateFormat('d MMM yyyy', 'id_ID').format(date);

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int? parseRupiah(String input) {
  final text = input.trim();
  // Never silently turn pasted decimals or separators into a different sum.
  if (!RegExp(r'^\d{1,12}$').hasMatch(text)) return null;
  final value = int.tryParse(text);
  return value != null && value <= maxAmount ? value : null;
}

String? validateRupiah(String? input, {bool allowZero = false}) {
  final value = parseRupiah(input ?? '');
  if (value == null) {
    return 'Gunakan rupiah bulat, maksimal 12 digit, tanpa titik/koma.';
  }
  if (!allowZero && value == 0) return 'Nominal harus lebih besar dari nol.';
  return null;
}
