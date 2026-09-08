import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../../calendar/views/calendar_view.dart';
import '../view_models/ledger_view_model.dart';
import 'account_widgets.dart';
import 'entry_presentation.dart';
import 'form_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  _HomeTab _tab = _HomeTab.overview;
  bool _showArchivedAccounts = false;
  Timer? _calendarDateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCalendarDateRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCalendarDate();
    }
  }

  void _refreshCalendarDate() {
    if (!mounted) return;
    ref.invalidate(currentDateProvider);
    ref.read(calendarStateProvider.notifier).refreshToday();
    _scheduleCalendarDateRefresh();
  }

  void _scheduleCalendarDateRefresh() {
    _calendarDateTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _calendarDateTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      _refreshCalendarDate,
    );
  }

  @override
  void dispose() {
    _calendarDateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _open(String route) {
    ref.read(financeActionsProvider.notifier).clearError();
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(financeSnapshotProvider);
    final accounts = snapshot.asData?.value.accounts;
    final ready = accounts != null;
    final hasActiveAccount = accounts?.any((account) => !account.isArchived);
    final addAccount = _tab == _HomeTab.accounts || hasActiveAccount != true;
    final selectedCalendarDay = _tab == _HomeTab.calendar
        ? ref.watch(calendarStateProvider.select((value) => value.selectedDay))
        : null;
    final primaryRoute = addAccount
        ? '/accounts/new'
        : selectedCalendarDay != null
        ? '/transactions/new?date=${civilDate(selectedCalendarDay)}'
        : '/transactions/new';
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.spa_outlined, color: forest),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waras Arta',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('manage-categories'),
            tooltip: 'Kelola kategori',
            onPressed: () => context.push('/categories'),
            icon: const Icon(Icons.category_outlined),
          ),
          PopupMenuButton<_HomeMenuAction>(
            key: const Key('more-menu'),
            tooltip: 'Menu lainnya',
            onSelected: (action) {
              switch (action) {
                case _HomeMenuAction.backup:
                  context.push('/backup');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeMenuAction.backup,
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Backup & pulihkan data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: snapshot.when(
              skipLoadingOnReload: false,
              data: (data) => _content(data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FormMessage(
                      'Data lokal belum dapat dibaca. Jangan hapus data aplikasi; coba buka kembali.',
                      isError: true,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(financeSnapshotProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: ready
          ? FloatingActionButton.extended(
              key: const Key('primary-action'),
              onPressed: () => _open(primaryRoute),
              icon: const Icon(Icons.add),
              label: Text(addAccount ? 'Tambah rekening' : 'Catat transaksi'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (value) => setState(() {
          _tab = _HomeTab.values[value];
        }),
        destinations: const [
          NavigationDestination(
            key: Key('overview-tab'),
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Ikhtisar',
          ),
          NavigationDestination(
            key: Key('history-tab'),
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Riwayat',
          ),
          NavigationDestination(
            key: Key('calendar-tab'),
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Kalender',
          ),
          NavigationDestination(
            key: Key('accounts-tab'),
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Rekening',
          ),
        ],
      ),
    );
  }

  Widget _content(FinanceSnapshot data) {
    final names = {
      for (final account in data.accounts) account.id: account.name,
    };
    if (_tab == _HomeTab.calendar) {
      return CalendarView(accountNames: names);
    }
    final activeAccounts = data.accounts
        .where((account) => !account.isArchived)
        .toList(growable: false);
    final primaryAccounts = activeAccounts
        .where((account) => account.balanceGroup == AccountBalanceGroup.primary)
        .toList(growable: false);
    final savingsInvestmentAccounts = activeAccounts
        .where(
          (account) =>
              account.balanceGroup == AccountBalanceGroup.savingsInvestment,
        )
        .toList(growable: false);
    final archivedAccounts = data.accounts
        .where((account) => account.isArchived)
        .toList(growable: false);
    final accountRows = _tab == _HomeTab.accounts
        ? _accountRows(
            primaryAccounts: primaryAccounts,
            savingsInvestmentAccounts: savingsInvestmentAccounts,
            archivedAccounts: archivedAccounts,
            data: data,
          )
        : const <Widget>[];
    final intro = <Widget>[
      if (_tab == _HomeTab.overview) ...[
        const Text(
          'CATAT, ATUR, TETAP WARAS.',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            color: forest,
          ),
        ),
        const SizedBox(height: 16),
        _BalanceCard(total: data.primaryBalance, count: primaryAccounts.length),
        const SizedBox(height: 24),
      ] else ...[
        Text(
          _tab == _HomeTab.history
              ? 'Jejak keuanganmu'
              : 'Tempat uangmu tersimpan',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _tab == _HomeTab.history
              ? 'Setiap catatan, satu langkah lebih teratur.'
              : 'Pisahkan uang rutin dari simpanan dan investasi.',
        ),
        const SizedBox(height: 24),
      ],
      if (_tab != _HomeTab.accounts) ...[
        const _MonthSelector(),
        const SizedBox(height: 16),
        if (_tab == _HomeTab.overview) ...[
          _MonthlyTotals(data: data),
          const SizedBox(height: 24),
          const Text(
            'Catatan terbaru',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('Pada bulan yang dipilih'),
        ] else
          Text(
            '${data.totalEntries} catatan • termasuk transfer dan penyesuaian saldo',
          ),
        const SizedBox(height: 16),
      ],
    ];
    final entries = _tab == _HomeTab.overview
        ? data.entries.take(5).toList()
        : data.entries;
    final rowCount = _tab == _HomeTab.accounts
        ? accountRows.length
        : entries.length;
    final contentIsEmpty = _tab == _HomeTab.accounts
        ? data.accounts.isEmpty
        : entries.isEmpty;
    final footer = <Widget>[
      if (contentIsEmpty)
        _EmptyCard(
          title: _tab == _HomeTab.accounts
              ? 'Belum ada rekening'
              : data.accounts.isEmpty
              ? 'Mulai dari satu rekening'
              : 'Belum ada catatan bulan ini',
          description: _tab == _HomeTab.accounts
              ? 'Tambahkan dompet, bank, atau e-wallet pertamamu.'
              : data.accounts.isEmpty
              ? 'Tambahkan dompet atau bank, lalu catat uang yang masuk dan keluar.'
              : 'Transaksi akan muncul di sini sesuai tanggal kejadiannya.',
          icon: _tab == _HomeTab.accounts || data.accounts.isEmpty
              ? Icons.wallet_outlined
              : Icons.edit_note,
        ),
      if (_tab == _HomeTab.overview && data.totalEntries > 5)
        TextButton(
          onPressed: () => setState(() => _tab = _HomeTab.history),
          child: const Text('Lihat semua catatan'),
        ),
      if (_tab == _HomeTab.history && data.hasMore)
        OutlinedButton(
          onPressed: () => ref.read(ledgerFilterProvider.notifier).loadMore(),
          child: Text(
            'Muat 50 berikutnya (${data.entries.length}/${data.totalEntries})',
          ),
        ),
      const SizedBox(height: 24),
      const FormMessage(
        'Versi awal • Data tersimpan di perangkat. Buat backup terenkripsi secara berkala.',
      ),
      const SizedBox(height: 90),
    ];

    return ListView.builder(
      key: PageStorageKey('ledger-tab-${_tab.name}'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: intro.length + rowCount + footer.length,
      itemBuilder: (context, index) {
        if (index < intro.length) return intro[index];
        final row = index - intro.length;
        if (row < rowCount) {
          if (_tab == _HomeTab.accounts) {
            return accountRows[row];
          }
          return _EntryRow(
            entry: entries[row],
            names: names,
            first: row == 0,
            last: row == rowCount - 1,
          );
        }
        return footer[row - rowCount];
      },
    );
  }

  List<Widget> _accountRows({
    required List<FinanceAccount> primaryAccounts,
    required List<FinanceAccount> savingsInvestmentAccounts,
    required List<FinanceAccount> archivedAccounts,
    required FinanceSnapshot data,
  }) {
    if (data.accounts.isEmpty) return const [];

    Widget accountCard(FinanceAccount account) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AccountCard(
        account: account,
        onTap: () => _open('/accounts/${account.id}'),
      ),
    );

    return [
      _AccountSectionHeader(
        title: AccountBalanceGroup.primary.label,
        total: data.primaryBalance,
        count: primaryAccounts.length,
        totalKey: const Key('primary-accounts-total'),
      ),
      const SizedBox(height: 10),
      if (primaryAccounts.isEmpty)
        const _AccountSectionEmpty(
          message: 'Belum ada rekening untuk saldo utama.',
        )
      else
        for (final account in primaryAccounts) accountCard(account),
      const SizedBox(height: 14),
      _AccountSectionHeader(
        title: AccountBalanceGroup.savingsInvestment.label,
        total: data.savingsInvestmentBalance,
        count: savingsInvestmentAccounts.length,
        totalKey: const Key('savings-investment-total'),
      ),
      const SizedBox(height: 10),
      if (savingsInvestmentAccounts.isEmpty)
        const _AccountSectionEmpty(
          message: 'Belum ada rekening simpanan atau investasi. Pilih kelompok ini saat menambah rekening.',
        )
      else
        for (final account in savingsInvestmentAccounts) accountCard(account),
      if (archivedAccounts.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Divider(),
        SwitchListTile.adaptive(
          key: const Key('show-archived-accounts'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Rekening diarsipkan (${archivedAccounts.length})',
            key: const Key('archived-account-count'),
          ),
          subtitle: const Text(
            'Tidak dapat dipakai untuk transaksi baru; riwayat tetap tersimpan.',
          ),
          value: _showArchivedAccounts,
          onChanged: (value) {
            setState(() => _showArchivedAccounts = value);
          },
        ),
        if (_showArchivedAccounts) ...[
          const SizedBox(height: 4),
          for (final account in archivedAccounts) accountCard(account),
        ],
      ],
    ];
  }
}

enum _HomeMenuAction { backup }

enum _HomeTab { overview, history, calendar, accounts }

class _AccountSectionHeader extends StatelessWidget {
  const _AccountSectionHeader({
    required this.title,
    required this.total,
    required this.count,
    required this.totalKey,
  });

  final String title;
  final int total;
  final int count;
  final Key totalKey;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '$count rekening',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                ),
              ),
            ],
          );
          final amount = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              formatRupiah(total),
              key: totalKey,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          );

          if (stacked) {
            return Column(
              key: ValueKey('account-section-stacked-$title'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 8), amount],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 12),
              Flexible(child: amount),
            ],
          );
        },
      ),
    ),
  );
}

class _AccountSectionEmpty extends StatelessWidget {
  const _AccountSectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.total, required this.count});
  final int total;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: forest,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SALDO UTAMA',
          style: TextStyle(
            color: Color(0xFFD6E4D9),
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRupiah(total),
            key: const Key('primary-balance-total'),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '$count rekening • tidak termasuk simpanan & investasi',
          style: const TextStyle(color: Color(0xFFD6E4D9)),
        ),
      ],
    ),
  );
}

class _MonthSelector extends ConsumerWidget {
  const _MonthSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(
      ledgerFilterProvider.select((filter) => filter.month),
    );
    final now = DateTime.now();
    return Row(
      children: [
        IconButton(
          tooltip: 'Bulan sebelumnya',
          onPressed: month.isAfter(DateTime(2000))
              ? () => ref.read(ledgerFilterProvider.notifier).moveMonth(-1)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            formatMonth(month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Bulan berikutnya',
          onPressed: month.isBefore(DateTime(now.year, now.month))
              ? () => ref.read(ledgerFilterProvider.notifier).moveMonth(1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _MonthlyTotals extends StatelessWidget {
  const _MonthlyTotals({required this.data});
  final FinanceSnapshot data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          final income = _Metric(
            label: 'Pemasukan',
            amount: data.income,
            icon: Icons.south_west,
            color: forest,
          );
          final expense = _Metric(
            label: 'Pengeluaran',
            amount: data.expense,
            icon: Icons.north_east,
            color: const Color(0xFF9D492B),
          );
          return stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [income, const SizedBox(height: 12), expense],
                )
              : Row(
                  children: [
                    Expanded(child: income),
                    const SizedBox(width: 12),
                    Expanded(child: expense),
                  ],
                );
        },
      ),
      const SizedBox(height: 12),
      Text(
        'Selisih bulan ini: ${formatRupiah(data.net)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      const Text(
        'Tidak termasuk transfer dan penyesuaian saldo, termasuk saldo awal.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });
  final String label;
  final int amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            formatRupiah(amount),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.onTap});
  final FinanceAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: account.isArchived ? .65 : 1,
    child: Card(
      child: InkWell(
        key: ValueKey('account-${account.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(accountIconFor(account.type), color: forest),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(account.type.label),
                            if (account.isArchived)
                              const AccountStatusBadge(archived: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatRupiah(account.balance),
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              if (account.balance < 0) ...[
                const SizedBox(height: 4),
                const Text(
                  'Saldo tercatat negatif. Periksa kelengkapan catatan.',
                  style: TextStyle(color: Color(0xFF9D492B)),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.description,
    required this.icon,
  });
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 36, color: forest),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(description),
        ],
      ),
    ),
  );
}
