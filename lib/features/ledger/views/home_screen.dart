import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../budgets/view_models/budget_view_model.dart';
import '../../budgets/views/budget_list_screen.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../../calendar/views/calendar_view.dart';
import '../view_models/ledger_view_model.dart';
import '../view_models/overview_charts_view_model.dart';
import 'account_widgets.dart';
import 'compact_transaction_row.dart';
import 'form_widgets.dart';
import 'overview_charts_section.dart';

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
    ref.read(budgetFilterProvider.notifier).refreshToday();
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
    final isBudgetTab = _tab == _HomeTab.budgets;
    final addAccount =
        !isBudgetTab && (_tab == _HomeTab.accounts || hasActiveAccount != true);
    final selectedCalendarDay = _tab == _HomeTab.calendar
        ? ref.watch(calendarStateProvider.select((value) => value.selectedDay))
        : null;
    final primaryRoute = addAccount
        ? '/accounts/new'
        : selectedCalendarDay != null
        ? '/transactions/new?date=${civilDate(selectedCalendarDay)}'
        : '/transactions/new';
    final navigationLabelBehavior =
        MediaQuery.sizeOf(context).width <= 320 &&
            MediaQuery.textScalerOf(context).scale(1) >= 2
        ? NavigationDestinationLabelBehavior.alwaysHide
        : MediaQuery.sizeOf(context).width < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3
        ? NavigationDestinationLabelBehavior.onlyShowSelected
        : NavigationDestinationLabelBehavior.alwaysShow;
    final Widget? primaryAction;
    if (isBudgetTab) {
      primaryAction = const BudgetAddButton();
    } else if (ready) {
      primaryAction = FloatingActionButton.extended(
        key: const Key('primary-action'),
        onPressed: () => _open(primaryRoute),
        icon: const Icon(Icons.add),
        label: Text(addAccount ? 'Tambah rekening' : 'Catat transaksi'),
      );
    } else {
      primaryAction = null;
    }
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
            child: isBudgetTab
                ? const BudgetListScreen(embedded: true)
                : snapshot.when(
                    skipLoadingOnReload: false,
                    data: (data) => _content(data),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
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
                            onPressed: () =>
                                ref.invalidate(financeSnapshotProvider),
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
      floatingActionButton: primaryAction == null
          ? null
          : KeyedSubtree(
              key: const ValueKey('home-fab-slot'),
              child: primaryAction,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        labelBehavior: navigationLabelBehavior,
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
            key: Key('budget-tab'),
            icon: Icon(Icons.donut_small_outlined),
            selectedIcon: Icon(Icons.donut_small),
            label: 'Anggaran',
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
    final overviewCharts = _tab == _HomeTab.overview
        ? ref.watch(overviewChartsProvider)
        : null;
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
        _BalanceCard(
          total: data.primaryBalance,
          count: primaryAccounts.length,
          income: data.income,
          expense: data.expense,
          onCashflowTap: () {
            final month = ref.read(ledgerFilterProvider).month;
            final monthQuery =
                '${month.year.toString().padLeft(4, '0')}-'
                '${month.month.toString().padLeft(2, '0')}';
            _open('/summary?month=$monthQuery');
          },
        ),
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
          overviewCharts!.when(
            skipLoadingOnReload: true,
            data: (charts) => OverviewChartsSection(snapshot: charts),
            loading: () => const _OverviewChartsLoading(),
            error: (_, _) => _OverviewChartsError(
              onRetry: () => ref.invalidate(overviewChartsProvider),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Catatan terbaru',
            key: Key('recent-transactions-heading'),
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
          return CompactTransactionRow(
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

enum _HomeTab { overview, history, calendar, budgets, accounts }

class _OverviewChartsLoading extends StatelessWidget {
  const _OverviewChartsLoading();

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('overview-charts-loading'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Tren terkini',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Menyiapkan diagram dari catatan lokal…',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _OverviewChartsError extends StatelessWidget {
  const _OverviewChartsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('overview-charts-error'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Tren terkini',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Diagram belum dapat dimuat. Catatan keuanganmu tetap aman.',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('retry-overview-charts'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

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
  const _BalanceCard({
    required this.total,
    required this.count,
    required this.income,
    required this.expense,
    required this.onCashflowTap,
  });

  final int total;
  final int count;
  final int income;
  final int expense;
  final VoidCallback onCashflowTap;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('balance-summary'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: forest,
      borderRadius: BorderRadius.circular(24),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 250 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        final balance = Column(
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
              '$count rekening',
              style: const TextStyle(color: Color(0xFFD6E4D9)),
            ),
          ],
        );
        final chart = _MonthlyCashflowChart(
          income: income,
          expense: expense,
          wide: stacked,
          onTap: onCashflowTap,
        );

        if (stacked) {
          return Column(
            key: const Key('balance-summary-stacked'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              balance,
              const SizedBox(height: 22),
              Align(child: chart),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: balance),
            const SizedBox(width: 16),
            chart,
          ],
        );
      },
    ),
  );
}

class _MonthlyCashflowChart extends StatelessWidget {
  const _MonthlyCashflowChart({
    required this.income,
    required this.expense,
    required this.wide,
    required this.onTap,
  });

  static const _incomeColor = Color(0xFFA5D6A7);
  static const _expenseColor = Color(0xFFFF8A80);
  static const _emptyColor = Color(0x4DFFFFFF);

  final int income;
  final int expense;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final safeIncome = math.max(0, income);
    final safeExpense = math.max(0, expense);
    final empty = safeIncome == 0 && safeExpense == 0;
    final semanticsLabel = empty
        ? 'Arus kas bulan terpilih, belum ada pemasukan atau pengeluaran.'
        : 'Arus kas bulan terpilih, pemasukan '
              '${formatRupiah(safeIncome)}, pengeluaran '
              '${formatRupiah(safeExpense)}.';

    return Semantics(
      key: const Key('monthly-cashflow-chart'),
      container: true,
      button: true,
      onTap: onTap,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('monthly-cashflow-summary-link'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: wide ? 200 : 116,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ARUS BULAN DIPILIH',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD6E4D9),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CustomPaint(
                    key: const Key('monthly-cashflow-pie'),
                    painter: _MonthlyCashflowPiePainter(
                      income: safeIncome,
                      expense: safeExpense,
                      incomeColor: _incomeColor,
                      expenseColor: _expenseColor,
                      emptyColor: _emptyColor,
                    ),
                    child: SizedBox.square(
                      dimension: 84,
                      child: empty
                          ? const Center(
                              child: Text(
                                '—',
                                style: TextStyle(
                                  color: Color(0xFFD6E4D9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: const [
                      _CashflowLegend(
                        legendKey: Key('monthly-cashflow-income'),
                        color: _incomeColor,
                        label: 'Pemasukan',
                      ),
                      _CashflowLegend(
                        legendKey: Key('monthly-cashflow-expense'),
                        color: _expenseColor,
                        label: 'Pengeluaran',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const FittedBox(
                    key: Key('monthly-cashflow-summary-affordance'),
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lihat ringkasan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CashflowLegend extends StatelessWidget {
  const _CashflowLegend({
    required this.legendKey,
    required this.color,
    required this.label,
  });

  final Key legendKey;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    key: legendKey,
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 8),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    ),
  );
}

class _MonthlyCashflowPiePainter extends CustomPainter {
  const _MonthlyCashflowPiePainter({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.emptyColor,
  });

  final int income;
  final int expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = income + expense;

    if (total == 0) {
      canvas.drawCircle(center, radius, Paint()..color = emptyColor);
    } else if (income == 0) {
      canvas.drawCircle(center, radius, Paint()..color = expenseColor);
    } else if (expense == 0) {
      canvas.drawCircle(center, radius, Paint()..color = incomeColor);
    } else {
      final incomeSweep = 2 * math.pi * (income / total);
      const startAngle = -math.pi / 2;
      canvas
        ..drawArc(
          rect,
          startAngle,
          incomeSweep,
          true,
          Paint()..color = incomeColor,
        )
        ..drawArc(
          rect,
          startAngle + incomeSweep,
          2 * math.pi - incomeSweep,
          true,
          Paint()..color = expenseColor,
        );
    }

    canvas.drawCircle(
      center,
      radius - .75,
      Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MonthlyCashflowPiePainter oldDelegate) =>
      income != oldDelegate.income ||
      expense != oldDelegate.expense ||
      incomeColor != oldDelegate.incomeColor ||
      expenseColor != oldDelegate.expenseColor ||
      emptyColor != oldDelegate.emptyColor;
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
    key: const Key('monthly-totals'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        key: const Key('monthly-totals-row'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Metric(
              metricKey: const Key('monthly-metric-income'),
              label: 'Pemasukan',
              amount: data.income,
              icon: Icons.south_west,
              color: forest,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              metricKey: const Key('monthly-metric-expense'),
              label: 'Pengeluaran',
              amount: data.expense,
              icon: Icons.north_east,
              color: const Color(0xFF9D492B),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Kotak selisih
      Row(
        key: const Key('monthly-metric-net'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Metric(
              metricKey: const Key('monthly-metric-net'),
              label: 'Selisih',
              amount: data.net,
              icon: Icons.compare_arrows,
              color: data.net >= 0 ? forest : const Color(0xFF9D492B),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.metricKey,
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final Key metricKey;
  final String label;
  final int amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final formattedAmount = formatRupiah(amount);
    return Semantics(
      key: metricKey,
      container: true,
      label: '$label, $formattedAmount',
      child: ExcludeSemantics(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formattedAmount,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
