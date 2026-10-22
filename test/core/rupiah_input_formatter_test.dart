import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/core/formatters.dart';
import 'package:waras_arta/core/rupiah_input_formatter.dart';

TextEditingValue value(String text, {int? cursor}) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

void main() {
  const formatter = RupiahInputFormatter();
  const signed = RupiahInputFormatter(allowNegative: true);

  test('groups digits as they are typed and keeps cursor at the end', () {
    var current = value('');
    for (final digit in '1500000'.split('')) {
      current = formatter.formatEditUpdate(
        current,
        value('${current.text}$digit'),
      );
      expect(current.selection.baseOffset, current.text.length);
    }
    expect(current.text, '1.500.000');
    expect(parseRupiah(current.text), 1500000);
  });

  test('supports zero, empty input, and all 12 digits', () {
    for (final (input, output) in [
      ('0', '0'),
      ('00025', '00.025'),
      ('999999999999', '999.999.999.999'),
      ('1.250.000', '1.250.000'),
      (' 25000\n', '25.000'),
    ]) {
      expect(formatter.formatEditUpdate(value(''), value(input)).text, output);
    }
    expect(formatter.formatEditUpdate(value('25.000'), value('')).text, '');
  });

  test('rejects decimals, malformed groups, signs, currency, and overflow', () {
    final old = value('25.000');
    for (final input in [
      '15,50',
      '15.50',
      '1,000',
      '25000.50',
      'Rp 15.000',
      '1..000',
      '1234.567',
      '25 000',
      '25\n000',
      '+1000',
      '-1000',
      '1e3',
      'abc',
      '1000000000000',
      '1.000.000.000.000',
    ]) {
      expect(formatter.formatEditUpdate(old, value(input)), old, reason: input);
      final empty = value('');
      expect(
        formatter.formatEditUpdate(empty, value(input)),
        empty,
        reason: input,
      );
    }
  });

  test(
    'keeps editing cursor anchored to digits when inserting in the middle',
    () {
      final result = formatter.formatEditUpdate(
        value('12.345', cursor: 1),
        value('192.345', cursor: 2),
      );
      expect(result.text, '192.345');
      expect(result.selection.baseOffset, 2);
      final regrouped = formatter.formatEditUpdate(
        value('123.456', cursor: 3),
        value('1234.456', cursor: 4),
      );
      expect(regrouped.text, '1.234.456');
      expect(regrouped.selection.baseOffset, 5);
    },
  );

  test('preserves a ranged selection while regrouping', () {
    final result = formatter.formatEditUpdate(
      value(''),
      const TextEditingValue(
        text: '1234567',
        selection: TextSelection(
          baseOffset: 6,
          extentOffset: 2,
          isDirectional: true,
        ),
      ),
    );
    expect(result.text, '1.234.567');
    expect(result.selection.baseOffset, 8);
    expect(result.selection.extentOffset, 3);
    expect(result.selection.isDirectional, isTrue);
  });

  test(
    'rejects a decimal paste replacing a selection with matching digits',
    () {
      const old = TextEditingValue(
        text: '15.500',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(formatter.formatEditUpdate(old, value('15.50')), old);
      expect(formatter.formatEditUpdate(old, value('1.550')).text, '1.550');
    },
  );

  test(
    'inserting and deleting digits at every cursor position preserves value',
    () {
      for (final amount in [0, 999, 1000, 1234567, 99999999999]) {
        final text = formatRupiahInput(amount);
        for (var index = 0; index <= text.length; index++) {
          final updated = text.replaceRange(index, index, '8');
          final result = formatter.formatEditUpdate(
            value(text, cursor: index),
            value(updated, cursor: index + 1),
          );
          expect(
            parseRupiah(result.text),
            int.parse(updated.replaceAll('.', '')),
          );
          expect(
            result.selection.extentOffset,
            inInclusiveRange(0, result.text.length),
          );
        }
        for (var index = 0; index < text.length; index++) {
          if (text[index] == '.') continue;
          final updated = text.replaceRange(index, index + 1, '');
          final raw = updated.replaceAll('.', '');
          final result = formatter.formatEditUpdate(
            value(text, cursor: index + 1),
            value(updated, cursor: index),
          );
          expect(parseRupiah(result.text), raw.isEmpty ? null : int.parse(raw));
          expect(
            result.selection.extentOffset,
            inInclusiveRange(0, result.text.length),
          );
        }
      }
    },
  );

  test('backspace on a separator removes the preceding digit', () {
    final result = formatter.formatEditUpdate(
      value('12.345', cursor: 3),
      value('12345', cursor: 2),
    );
    expect(result.text, '1.345');
    expect(result.selection.baseOffset, 1);
    expect(parseRupiah(result.text), 1345);
  });

  test('forward delete on a separator removes the following digit', () {
    final result = formatter.formatEditUpdate(
      value('12.345', cursor: 2),
      value('12345', cursor: 2),
    );
    expect(result.text, '1.245');
    expect(result.selection.baseOffset, 3);
  });

  test(
    'deleting a digit regroups and replacing a selection preserves amount',
    () {
      final deleted = formatter.formatEditUpdate(
        value('12.345', cursor: 4),
        value('12.45', cursor: 3),
      );
      expect(deleted.text, '1.245');
      expect(deleted.selection.baseOffset, 3);
      final replaced = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '12.345',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
        ),
        value('1945', cursor: 2),
      );
      expect(replaced.text, '1.945');
      expect(replaced.selection.baseOffset, 3);
    },
  );

  test(
    'signed balance permits intermediate minus, negative, zero, and clearing',
    () {
      expect(signed.formatEditUpdate(value(''), value('-')).text, '-');
      final result = signed.formatEditUpdate(value('-'), value('-12500'));
      expect(result.text, '-12.500');
      expect(parseSignedRupiah(result.text), -12500);
      expect(signed.formatEditUpdate(result, value('0')).text, '0');
      expect(signed.formatEditUpdate(result, value('')).text, '');
      expect(
        signed.formatEditUpdate(value(''), value('-999999999999')).text,
        '-999.999.999.999',
      );
      final positive = signed.formatEditUpdate(
        value('12.500'),
        value('-12.500'),
      );
      expect(positive.text, '-12.500');
      expect(signed.formatEditUpdate(positive, value('12.500')).text, '12.500');
      for (final input in ['--10', '+1000', '-1,50', '-1000000000000']) {
        final empty = value('');
        expect(signed.formatEditUpdate(empty, value(input)), empty);
      }
    },
  );

  test('leaves selection-only and composing IME updates untouched', () {
    final moved = value('12.500', cursor: 1);
    expect(formatter.formatEditUpdate(value('12.500'), moved), moved);
    const composing = TextEditingValue(
      text: '12500',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    expect(formatter.formatEditUpdate(value(''), composing), composing);
    expect(
      formatter.formatEditUpdate(composing, value('12500')).text,
      '12.500',
    );
    expect(
      formatter.formatEditUpdate(composing, value('125000')).text,
      '125.000',
    );
  });

  testWidgets('formats actual field typing, paste, invalid paste, and clear', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: const [RupiahInputFormatter()],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '1250000');
    expect(controller.text, '1.250.000');
    expect(parseRupiah(controller.text), 1250000);
    await tester.enterText(find.byType(TextField), '15,50');
    expect(controller.text, '1.250.000');
    await tester.enterText(find.byType(TextField), '25.000');
    expect(controller.text, '25.000');
    await tester.enterText(find.byType(TextField), '');
    expect(controller.text, '');
  });
}
