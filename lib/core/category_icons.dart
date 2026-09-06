import 'package:flutter/material.dart';

import '../domain/finance.dart';

class CategoryIconOption {
  const CategoryIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

/// A deliberately small, stable catalog. The database stores [key], never an
/// IconData code point, so a Flutter upgrade cannot silently change user data.
const categoryIconOptions = <CategoryIconOption>[
  CategoryIconOption(
    key: 'payments',
    label: 'Uang',
    icon: Icons.payments_outlined,
  ),
  CategoryIconOption(key: 'work', label: 'Pekerjaan', icon: Icons.work_outline),
  CategoryIconOption(
    key: 'storefront',
    label: 'Usaha',
    icon: Icons.storefront_outlined,
  ),
  CategoryIconOption(
    key: 'redeem',
    label: 'Hadiah',
    icon: Icons.redeem_outlined,
  ),
  CategoryIconOption(
    key: 'restaurant',
    label: 'Makan',
    icon: Icons.restaurant_outlined,
  ),
  CategoryIconOption(
    key: 'directions_car',
    label: 'Transportasi',
    icon: Icons.directions_car_outlined,
  ),
  CategoryIconOption(
    key: 'shopping_bag',
    label: 'Belanja',
    icon: Icons.shopping_bag_outlined,
  ),
  CategoryIconOption(
    key: 'receipt_long',
    label: 'Tagihan',
    icon: Icons.receipt_long_outlined,
  ),
  CategoryIconOption(
    key: 'medical_services',
    label: 'Kesehatan',
    icon: Icons.medical_services_outlined,
  ),
  CategoryIconOption(
    key: 'movie',
    label: 'Hiburan',
    icon: Icons.movie_outlined,
  ),
  CategoryIconOption(
    key: 'subscriptions',
    label: 'Langganan',
    icon: Icons.subscriptions_outlined,
  ),
  CategoryIconOption(key: 'home', label: 'Rumah', icon: Icons.home_outlined),
  CategoryIconOption(
    key: 'school',
    label: 'Pendidikan',
    icon: Icons.school_outlined,
  ),
  CategoryIconOption(
    key: 'flight',
    label: 'Perjalanan',
    icon: Icons.flight_outlined,
  ),
  CategoryIconOption(
    key: 'savings',
    label: 'Tabungan',
    icon: Icons.savings_outlined,
  ),
  CategoryIconOption(
    key: 'family_restroom',
    label: 'Keluarga',
    icon: Icons.family_restroom_outlined,
  ),
  CategoryIconOption(key: 'pets', label: 'Hewan', icon: Icons.pets_outlined),
  CategoryIconOption(
    key: 'checkroom',
    label: 'Pakaian',
    icon: Icons.checkroom_outlined,
  ),
  CategoryIconOption(
    key: 'local_grocery_store',
    label: 'Kebutuhan',
    icon: Icons.local_grocery_store_outlined,
  ),
  CategoryIconOption(
    key: 'sports_esports',
    label: 'Permainan',
    icon: Icons.sports_esports_outlined,
  ),
  CategoryIconOption(
    key: 'volunteer_activism',
    label: 'Donasi',
    icon: Icons.volunteer_activism_outlined,
  ),
  CategoryIconOption(
    key: 'account_balance',
    label: 'Keuangan',
    icon: Icons.account_balance_outlined,
  ),
  CategoryIconOption(
    key: 'category',
    label: 'Kategori',
    icon: Icons.category_outlined,
  ),
  CategoryIconOption(
    key: 'more_horiz',
    label: 'Lainnya',
    icon: Icons.more_horiz,
  ),
];

IconData categoryIconFor(String key) {
  for (final option in categoryIconOptions) {
    if (option.key == key) return option.icon;
  }
  return Icons.category_outlined;
}

String categoryIconLabelFor(String key) {
  for (final option in categoryIconOptions) {
    if (option.key == key) return option.label;
  }
  return 'Kategori';
}

String defaultCategoryIconKey(CategoryKind kind) =>
    kind == CategoryKind.income ? 'payments' : 'shopping_bag';
