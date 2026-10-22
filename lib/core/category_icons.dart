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

/// A stable catalog. The database stores [key], never an
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
  CategoryIconOption(key: 'bolt', label: 'Listrik', icon: Icons.bolt_outlined),
  CategoryIconOption(
    key: 'water_drop',
    label: 'Air',
    icon: Icons.water_drop_outlined,
  ),
  CategoryIconOption(
    key: 'local_gas_station',
    label: 'Bahan bakar',
    icon: Icons.local_gas_station_outlined,
  ),
  CategoryIconOption(
    key: 'laptop_mac',
    label: 'Laptop',
    icon: Icons.laptop_mac_outlined,
  ),
  CategoryIconOption(
    key: 'smartphone',
    label: 'Ponsel',
    icon: Icons.smartphone_outlined,
  ),
  CategoryIconOption(key: 'wifi', label: 'Internet', icon: Icons.wifi_outlined),
  CategoryIconOption(
    key: 'kitchen',
    label: 'Peralatan rumah',
    icon: Icons.kitchen_outlined,
  ),
  CategoryIconOption(
    key: 'construction',
    label: 'Perbaikan',
    icon: Icons.construction_outlined,
  ),
  CategoryIconOption(
    key: 'plumbing',
    label: 'Perpipaan',
    icon: Icons.plumbing_outlined,
  ),
  CategoryIconOption(
    key: 'local_parking',
    label: 'Parkir',
    icon: Icons.local_parking_outlined,
  ),
  CategoryIconOption(
    key: 'two_wheeler',
    label: 'Motor',
    icon: Icons.two_wheeler_outlined,
  ),
  CategoryIconOption(
    key: 'directions_bus',
    label: 'Angkutan umum',
    icon: Icons.directions_bus_outlined,
  ),
  CategoryIconOption(
    key: 'fitness_center',
    label: 'Olahraga',
    icon: Icons.fitness_center_outlined,
  ),
  CategoryIconOption(
    key: 'content_cut',
    label: 'Perawatan diri',
    icon: Icons.content_cut_outlined,
  ),
  CategoryIconOption(
    key: 'child_care',
    label: 'Anak',
    icon: Icons.child_care_outlined,
  ),
  CategoryIconOption(key: 'paid', label: 'Gaji', icon: Icons.paid_outlined),
  CategoryIconOption(
    key: 'request_quote',
    label: 'Honorarium',
    icon: Icons.request_quote_outlined,
  ),
  CategoryIconOption(
    key: 'design_services',
    label: 'Freelance',
    icon: Icons.design_services_outlined,
  ),
  CategoryIconOption(
    key: 'point_of_sale',
    label: 'Penjualan',
    icon: Icons.point_of_sale_outlined,
  ),
  CategoryIconOption(
    key: 'loyalty',
    label: 'Bonus',
    icon: Icons.loyalty_outlined,
  ),
  CategoryIconOption(
    key: 'trending_up',
    label: 'Investasi',
    icon: Icons.trending_up_outlined,
  ),
  CategoryIconOption(
    key: 'percent',
    label: 'Bunga',
    icon: Icons.percent_outlined,
  ),
  CategoryIconOption(
    key: 'pie_chart',
    label: 'Dividen',
    icon: Icons.pie_chart_outline,
  ),
  CategoryIconOption(
    key: 'currency_exchange',
    label: 'Cashback',
    icon: Icons.currency_exchange_outlined,
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
