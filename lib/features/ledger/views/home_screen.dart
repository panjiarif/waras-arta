import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/category_icons.dart';
import '../../../core/formatters.dart';
import '../../../domain/finance.dart';
import '../../calendar/view_models/calendar_view_model.dart';
import '../../calendar/views/calendar_view.dart';
import '../view_models/ledger_view_model.dart';
import 'account_widgets.dart';
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
    final visibleAccounts = _showArchivedAccounts
        ? data.accounts
        : activeAccounts;
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
        _BalanceCard(total: data.totalBalance, count: activeAccounts.length),
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
              : 'Saldo saat ini dari seluruh catatan.',
        ),
        const SizedBox(height: 24),
        if (_tab == _HomeTab.accounts) ...[
          SwitchListTile.adaptive(
            key: const Key('show-archived-accounts'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan rekening diarsipkan'),
            subtitle: const Text('Riwayat dan nama rekening tetap tersimpan.'),
            value: _showArchivedAccounts,
            onChanged: (value) {
              setState(() => _showArchivedAccounts = value);
            },
          ),
          const SizedBox(height: 8),
        ],
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
        ? visibleAccounts.length
        : entries.length;
    final footer = <Widget>[
      if (rowCount == 0)
        _EmptyCard(
          title: _tab == _HomeTab.accounts
              ? _showArchivedAccounts
                    ? 'Belum ada rekening'
                    : 'Belum ada rekening aktif'
              : data.accounts.isEmpty
              ? 'Mulai dari satu rekening'
              : 'Belum ada catatan bulan ini',
          description: _tab == _HomeTab.accounts
              ? _showArchivedAccounts
                    ? 'Tambahkan dompet, bank, atau e-wallet pertamamu.'
                    : 'Tambahkan rekening baru atau tampilkan rekening yang pernah diarsipkan.'
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
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _tab == _HomeTab.accounts
                ? _AccountCard(
                    account: visibleAccounts[row],
                    onTap: () => _open('/accounts/${visibleAccounts[row].id}'),
                  )
                : _EntryCard(entry: entries[row], names: names),
          );
        }
        return footer[row - rowCount];
      },
    );
  }
}

enum _HomeMenuAction { backup }

enum _HomeTab { overview, history, calendar, accounts }

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
          'TOTAL SALDO SAAT INI',
          style: TextStyle(
            color: Color(0xFFD6E4D9),
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          formatRupiah(total),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '$count rekening • seluruh tanggal',
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(accountIconFor(account.type), color: forest),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (account.isArchived)
                          const AccountStatusBadge(archived: true),
                      ],
                    ),
                    Text(account.type.label),
                    const SizedBox(height: 10),
                    Text(
                      formatRupiah(account.balance),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    if (account.balance < 0)
                      const Text(
                        'Saldo tercatat negatif. Periksa kelengkapan catatan.',
                        style: TextStyle(color: Color(0xFF9D492B)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry, required this.names});
  final FinanceEntry entry;
  final Map<int, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color =
        entry.kind == EntryKind.expense ||
            (entry.kind == EntryKind.adjustment && entry.amount < 0)
        ? const Color(0xFF9D492B)
        : forest;
    final route = entry.kind == EntryKind.transfer
        ? '${names[entry.accountId]} → ${names[entry.destinationAccountId]}'
        : names[entry.accountId] ?? 'Rekening';
    final prefix = switch (entry.kind) {
      EntryKind.income => '+ ',
      EntryKind.expense => '− ',
      EntryKind.adjustment when entry.amount > 0 => '+ ',
      _ => '',
    };
    final icon = entry.categoryIconKey != null
        ? categoryIconFor(entry.categoryIconKey!)
        : switch (entry.kind) {
            EntryKind.income => Icons.south_west,
            EntryKind.expense => Icons.north_east,
            EntryKind.transfer => Icons.swap_horiz,
            EntryKind.adjustment => Icons.savings_outlined,
          };
    return Card(
      child: InkWell(
        key: ValueKey('entry-${entry.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          ref.read(financeActionsProvider.notifier).clearError();
          context.push('/transactions/${entry.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.categoryName ?? entry.kind.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(route, style: const TextStyle(fontSize: 13)),
                    Text(
                      [
                        if (entry.parentCategoryName != null)
                          entry.parentCategoryName!,
                        entry.kind.label,
                        formatDate(entry.occurredAt),
                      ].join(' • '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (entry.categoryArchived)
                      const Text(
                        'Kategori diarsipkan',
                        style: TextStyle(fontSize: 12),
                      ),
                    if (entry.note.isNotEmpty &&
                        entry.note != 'Saldo awal') ...[
                      const SizedBox(height: 4),
                      Text(entry.note),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      '$prefix${formatRupiah(entry.amount)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
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
