import 'package:flutter/services.dart';

import 'formatters.dart';

/// Groups whole rupiah while preserving selection and rejecting ambiguous paste.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter({this.allowNegative = false});

  final bool allowNegative;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    if (newValue.text == oldValue.text && oldValue.composing.isCollapsed) {
      return newValue;
    }

    var text = newValue.text.trim();
    var selection = newValue.selection;
    final trimmedLeft = newValue.text.length - newValue.text.trimLeft().length;
    if (selection.isValid && trimmedLeft > 0) {
      selection = selection.copyWith(
        baseOffset: (selection.baseOffset - trimmedLeft).clamp(0, text.length),
        extentOffset: (selection.extentOffset - trimmedLeft).clamp(
          0,
          text.length,
        ),
      );
    }
    if (text.isEmpty || (allowNegative && text == '-')) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    final validAmount = allowNegative
        ? parseSignedRupiah(text) != null
        : parseRupiah(text) != null;

    var start = 0;
    while (start < oldValue.text.length &&
        start < newValue.text.length &&
        oldValue.text[start] == newValue.text[start]) {
      start++;
    }
    var oldEnd = oldValue.text.length;
    var newEnd = newValue.text.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldValue.text[oldEnd - 1] == newValue.text[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    var inserted = newValue.text.substring(start, newEnd);
    final removed = oldValue.text.substring(start, oldEnd);
    // A selected range describes the actual replacement more precisely than
    // matching prefixes/suffixes (a paste may reuse the old digits and dots).
    final oldSelection = oldValue.selection;
    if (oldSelection.isValid &&
        !oldSelection.isCollapsed &&
        oldSelection.end <= oldValue.text.length) {
      final prefix = oldValue.text.substring(0, oldSelection.start);
      final suffix = oldValue.text.substring(oldSelection.end);
      if (newValue.text.length >= prefix.length + suffix.length &&
          newValue.text.startsWith(prefix) &&
          newValue.text.endsWith(suffix)) {
        inserted = newValue.text.substring(
          prefix.length,
          newValue.text.length - suffix.length,
        );
      }
    }
    final editingDigits = RegExp(r'^\d*$').hasMatch(inserted);
    final editingSign = allowNegative && start == 0 && inserted == '-';
    // Editing digits inside a formatted value can temporarily break grouping.
    // Separators pasted from elsewhere must still form valid groups.
    if (!validAmount && !editingDigits && !editingSign) return oldValue;
    if (!RegExp(allowNegative ? r'^-?[\d.]+$' : r'^[\d.]+$').hasMatch(text)) {
      return oldValue;
    }

    // Backspace/Delete on a generated dot must remove an adjacent digit so the
    // cursor does not get stuck repeatedly recreating the same separator.
    if (inserted.isEmpty &&
        removed == '.' &&
        oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed) {
      final backwards = oldValue.selection.extentOffset > start;
      final digitIndex = backwards ? start - 1 : start;
      if (digitIndex >= 0 &&
          digitIndex < text.length &&
          RegExp(r'\d').hasMatch(text[digitIndex])) {
        text = text.replaceRange(digitIndex, digitIndex + 1, '');
        selection = TextSelection.collapsed(
          offset: backwards ? digitIndex : start,
        );
      }
    }

    final raw = text.replaceAll('.', '');
    final digits = raw.startsWith('-') ? raw.substring(1) : raw;
    if (digits.length > 12) return oldValue;
    final formatted = raw.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    int mapOffset(int offset) {
      final logical = text
          .substring(0, offset.clamp(0, text.length))
          .replaceAll('.', '')
          .length;
      if (logical == 0) return 0;
      var seen = 0;
      for (var index = 0; index < formatted.length; index++) {
        if (formatted[index] != '.') seen++;
        if (seen == logical) return index + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: mapOffset(selection.baseOffset),
              extentOffset: mapOffset(selection.extentOffset),
              affinity: selection.affinity,
              isDirectional: selection.isDirectional,
            )
          : TextSelection.collapsed(offset: formatted.length),
    );
  }
}
