import 'package:flutter/material.dart';

import '../../../core/category_icons.dart';
import '../../../domain/finance.dart';

extension FinanceEntryPresentation on FinanceEntry {
  bool get isSplitEntry => allocations.length > 1;

  bool get hasArchivedAllocation =>
      allocations.any((allocation) => allocation.categoryArchived);

  String get presentationTitle => isSplitEntry
      ? '${allocations.length} rincian'
      : categoryName ?? kind.label;

  String get compactPresentationTitle {
    if (isSplitEntry || allocations.isEmpty) return presentationTitle;
    final allocation = allocations.single;
    return allocation.categoryName.trim().toLowerCase() == 'umum'
        ? allocation.parentCategoryName
        : allocation.categoryName;
  }

  String? get presentationCategorySummary {
    if (allocations.isEmpty) return null;
    if (!isSplitEntry) return parentCategoryName;

    final labels = <String>[];
    for (final allocation in allocations) {
      final label =
          '${allocation.parentCategoryName}: '
          '${allocation.categoryName}';
      if (!labels.contains(label)) labels.add(label);
    }
    if (labels.length <= 2) return labels.join(' • ');
    return '${labels.take(2).join(' • ')} • +${labels.length - 2} lainnya';
  }

  IconData get presentationIcon {
    if (isSplitEntry) return Icons.call_split;
    final iconKey = categoryIconKey;
    if (iconKey != null) return categoryIconFor(iconKey);
    return switch (kind) {
      EntryKind.income => Icons.south_west,
      EntryKind.expense => Icons.north_east,
      EntryKind.transfer => Icons.swap_horiz,
      EntryKind.adjustment => Icons.savings_outlined,
    };
  }
}
