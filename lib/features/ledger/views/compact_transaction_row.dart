import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../view_models/ledger_view_model.dart';
import 'entry_presentation.dart';

/// Tampilan ringkas transaksi yang dipakai bersama oleh Ikhtisar, Riwayat,
/// dan daftar transaksi pada tanggal terpilih di Kalender.
class CompactTransactionRow extends ConsumerWidget {
  const CompactTransactionRow({
    super.key,
    required this.entry,
    required this.names,
    required this.first,
    required this.last,
  });

  final FinanceEntry entry;
  final Map<int, String> names;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color =
        entry.kind == EntryKind.expense ||
            (entry.kind == EntryKind.adjustment && entry.amount < 0)
        ? const Color(0xFF9D492B)
        : forest;
    String accountName(int? id) => names[id] ?? 'Rekening';
    final route = entry.kind == EntryKind.transfer
        ? '${accountName(entry.accountId)} → '
              '${accountName(entry.destinationAccountId)}'
        : accountName(entry.accountId);
    final absoluteAmount = formatRupiah(entry.amount.abs());
    final amount = switch (entry.kind) {
      EntryKind.income => '+ $absoluteAmount',
      EntryKind.expense => '− $absoluteAmount',
      EntryKind.adjustment when entry.amount > 0 => '+ $absoluteAmount',
      EntryKind.adjustment when entry.amount < 0 => '− $absoluteAmount',
      _ => absoluteAmount,
    };
    final title = entry.compactPresentationTitle;
    final date = formatDate(entry.occurredAt);
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(16) : Radius.zero,
      bottom: last ? const Radius.circular(16) : Radius.zero,
    );

    void openEntry() {
      ref.read(financeActionsProvider.notifier).clearError();
      context.push('/transactions/${entry.id}');
    }

    return Semantics(
      button: true,
      label: [
        entry.kind.label,
        title,
        amount,
        route,
        date,
        if (entry.hasArchivedAllocation) 'Kategori diarsipkan',
      ].join(', '),
      onTap: openEntry,
      child: ExcludeSemantics(
        child: Material(
          key: ValueKey('entry-row-${entry.id}'),
          color: Colors.white,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('entry-${entry.id}'),
            onTap: openEntry,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth < 282 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3;
                      final icon = Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          entry.presentationIcon,
                          color: color,
                          size: 21,
                        ),
                      );
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                icon,
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StackedEntryContent(
                                    entryId: entry.id,
                                    title: title,
                                    route: route,
                                    date: date,
                                    archived: entry.hasArchivedAllocation,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              key: ValueKey('entry-amount-fit-${entry.id}'),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                amount,
                                key: ValueKey('entry-amount-${entry.id}'),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TwoColumnEntryContent(
                              entryId: entry.id,
                              title: title,
                              route: route,
                              amount: amount,
                              date: date,
                              color: color,
                              archived: entry.hasArchivedAllocation,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (!last) const Divider(height: 1, indent: 64, endIndent: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoColumnEntryContent extends StatelessWidget {
  const _TwoColumnEntryContent({
    required this.entryId,
    required this.title,
    required this.route,
    required this.amount,
    required this.date,
    required this.color,
    required this.archived,
  });

  final int entryId;
  final String title;
  final String route;
  final String amount;
  final String date;
  final Color color;
  final bool archived;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _EntryTitle(
              entryId: entryId,
              title: title,
              archived: archived,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            key: ValueKey('entry-amount-$entryId'),
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Row(
        children: [
          Expanded(
            child: Text(
              route,
              key: ValueKey('entry-account-$entryId'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            date,
            key: ValueKey('entry-date-$entryId'),
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ],
  );
}

class _StackedEntryContent extends StatelessWidget {
  const _StackedEntryContent({
    required this.entryId,
    required this.title,
    required this.route,
    required this.date,
    required this.archived,
  });

  final int entryId;
  final String title;
  final String route;
  final String date;
  final bool archived;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _EntryTitle(entryId: entryId, title: title, archived: archived),
      const SizedBox(height: 3),
      Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          Text(
            route,
            key: ValueKey('entry-account-$entryId'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text('•', style: Theme.of(context).textTheme.bodySmall),
          Text(
            date,
            key: ValueKey('entry-date-$entryId'),
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ],
  );
}

class _EntryTitle extends StatelessWidget {
  const _EntryTitle({
    required this.entryId,
    required this.title,
    required this.archived,
  });

  final int entryId;
  final String title;
  final bool archived;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          title,
          key: ValueKey('entry-title-$entryId'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      if (archived) ...[
        const SizedBox(width: 4),
        const Tooltip(
          message: 'Kategori diarsipkan',
          child: Icon(Icons.archive_outlined, size: 15),
        ),
      ],
    ],
  );
}
