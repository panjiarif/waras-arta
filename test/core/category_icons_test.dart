import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waras_arta/core/category_icons.dart';
import 'package:waras_arta/domain/finance.dart';

void main() {
  test('every selectable icon is valid for persistence and backup', () {
    final keys = categoryIconOptions.map((option) => option.key).toList();
    expect(keys.toSet().length, keys.length);
    expect(categoryIconKeys.toSet().length, categoryIconKeys.length);
    expect(keys, unorderedEquals(categoryIconKeys));
    for (final option in categoryIconOptions) {
      expect(option.label.trim(), isNotEmpty);
      expect(categoryIconFor(option.key), option.icon);
      expect(categoryIconLabelFor(option.key), option.label);
    }
  });

  test('offers dedicated utility, device, and income icons', () {
    const expected = {
      'bolt': 'Listrik',
      'water_drop': 'Air',
      'local_gas_station': 'Bahan bakar',
      'laptop_mac': 'Laptop',
      'smartphone': 'Ponsel',
      'wifi': 'Internet',
      'local_parking': 'Parkir',
      'paid': 'Gaji',
      'request_quote': 'Honorarium',
      'design_services': 'Freelance',
      'point_of_sale': 'Penjualan',
      'loyalty': 'Bonus',
      'trending_up': 'Investasi',
      'percent': 'Bunga',
      'pie_chart': 'Dividen',
      'currency_exchange': 'Cashback',
    };
    for (final entry in expected.entries) {
      expect(categoryIconKeys, contains(entry.key));
      expect(categoryIconLabelFor(entry.key), entry.value);
      expect(categoryIconFor(entry.key), isNot(Icons.category_outlined));
    }
  });

  test('retains defaults and the display fallback for an unknown key', () {
    expect(defaultCategoryIconKey(CategoryKind.income), 'payments');
    expect(defaultCategoryIconKey(CategoryKind.expense), 'shopping_bag');
    expect(categoryIconFor('unknown'), Icons.category_outlined);
    expect(categoryIconLabelFor('unknown'), 'Kategori');
  });
}
