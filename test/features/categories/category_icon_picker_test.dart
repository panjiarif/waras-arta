import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/core/category_icons.dart';
import 'package:waras_arta/features/categories/views/category_widgets.dart';

void main() {
  for (final key in [
    'bolt',
    'water_drop',
    'local_gas_station',
    'laptop_mac',
    'paid',
    'currency_exchange',
  ]) {
    testWidgets(
      'selects $key from the expanded catalog and updates the field',
      (tester) async {
        final selected = ValueNotifier('payments');
        addTearDown(selected.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: selected,
                builder: (_, value, _) => CategoryIconField(
                  value: value,
                  onChanged: (key) => selected.value = key,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('category-icon-field')));
        await tester.pumpAndSettle();
        final icon = find.byKey(ValueKey('category-icon-$key'));
        await tester.scrollUntilVisible(
          icon,
          220,
          scrollable: find.descendant(
            of: find.byKey(const Key('category-icon-grid')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(selected.value, key);
        expect(find.text(categoryIconLabelFor(key)), findsOneWidget);
        expect(find.byType(CategoryIconPicker), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
