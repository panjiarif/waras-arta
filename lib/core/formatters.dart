import 'package:intl/intl.dart';

import '../domain/finance.dart';

final _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String formatRupiah(int value) => _rupiah.format(value);

/// Whole rupiah for editable fields, without the separately displayed Rp prefix.
String formatRupiahInput(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]}.',
);
String formatMonth(DateTime date) =>
    DateFormat('MMMM yyyy', 'id_ID').format(date);
String formatDate(DateTime date) =>
    DateFormat('d MMM yyyy', 'id_ID').format(date);
String formatDateTime(DateTime date) =>
    DateFormat('d MMM yyyy, HH.mm', 'id_ID').format(date);

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int? parseRupiah(String input) {
  final text = input.trim();
  // Only accept plain digits or correctly grouped Indonesian thousands.
  // Do not reinterpret decimals, commas, or malformed groups as whole rupiah.
  if (!RegExp(r'^(?:\d{1,12}|\d{1,3}(?:\.\d{3}){1,3})$').hasMatch(text)) {
    return null;
  }
  final digits = text.replaceAll('.', '');
  if (digits.length > 12) return null;
  final value = int.tryParse(digits);
  return value != null && value <= maxAmount ? value : null;
}

int? parseSignedRupiah(String input) {
  final text = input.trim();
  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  if (unsigned != unsigned.trim()) return null;
  final value = parseRupiah(unsigned);
  return value == null ? null : (negative ? -value : value);
}

String? validateRupiah(String? input, {bool allowZero = false}) {
  final value = parseRupiah(input ?? '');
  if (value == null) {
    return 'Gunakan rupiah bulat, maksimal 12 digit. Titik hanya untuk ribuan.';
  }
  if (!allowZero && value == 0) return 'Nominal harus lebih besar dari nol.';
  return null;
}

String? validateSignedRupiah(String? input) {
  if (parseSignedRupiah(input ?? '') == null) {
    return 'Gunakan rupiah bulat, maksimal 12 digit. Titik hanya untuk ribuan.';
  }
  return null;
}
