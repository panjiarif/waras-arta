import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/finance.dart';
import '../../../domain/finance_repository.dart';

class LedgerFilter {
  const LedgerFilter({required this.month, this.limit = 50});

  final DateTime month;
  final int limit;
}

final ledgerFilterProvider = NotifierProvider<LedgerViewModel, LedgerFilter>(
  LedgerViewModel.new,
);

class LedgerViewModel extends Notifier<LedgerFilter> {
  @override
  LedgerFilter build() {
    final now = DateTime.now();
    return LedgerFilter(month: DateTime(now.year, now.month));
  }

  void moveMonth(int delta) {
    final month = DateTime(state.month.year, state.month.month + delta);
    final now = DateTime.now();
    if (month.isBefore(DateTime(2000)) ||
        month.isAfter(DateTime(now.year, now.month))) {
      return;
    }
    state = LedgerFilter(month: month);
  }

  void showMonth(DateTime date) {
    state = LedgerFilter(month: DateTime(date.year, date.month));
  }

  void loadMore() {
    state = LedgerFilter(month: state.month, limit: state.limit + 50);
  }
}

final financeSnapshotProvider = StreamProvider<FinanceSnapshot>((ref) {
  final filter = ref.watch(ledgerFilterProvider);
  return ref
      .watch(financeRepositoryProvider)
      .watchMonth(filter.month, limit: filter.limit);
});

final financeEntryProvider = StreamProvider.autoDispose
    .family<FinanceEntry?, int>((ref, entryId) {
      return ref.watch(financeRepositoryProvider).watchEntry(entryId);
    });

class SaveState {
  const SaveState({this.isSaving = false, this.error});

  final bool isSaving;
  final String? error;
}

final financeActionsProvider = NotifierProvider<FinanceActions, SaveState>(
  FinanceActions.new,
);

class FinanceActions extends Notifier<SaveState> {
  @override
  SaveState build() => const SaveState();

  Future<bool> createAccount(AccountDraft draft) => _save(
    (repository) async => repository.createAccount(draft),
    occurredAt: draft.openedAt,
  );

  Future<bool> addEntry(EntryDraft draft) => _save(
    (repository) async => repository.addEntry(draft),
    occurredAt: draft.occurredAt,
  );

  Future<bool> updateEntry(int entryId, EntryDraft draft) => _save(
    (repository) => repository.updateEntry(entryId, draft),
    occurredAt: draft.occurredAt,
  );

  Future<bool> deleteEntry(int entryId) =>
      _save((repository) => repository.deleteEntry(entryId));

  void clearError() {
    if (!state.isSaving) state = const SaveState();
  }

  Future<bool> _save(
    Future<void> Function(FinanceRepository) action, {
    DateTime? occurredAt,
  }) async {
    if (state.isSaving) return false;
    state = const SaveState(isSaving: true);
    try {
      await action(ref.read(financeRepositoryProvider));
      if (!ref.mounted) return true;
      if (occurredAt != null) {
        ref.read(ledgerFilterProvider.notifier).showMonth(occurredAt);
      }
      state = const SaveState();
      return true;
    } on FinanceValidationException catch (error) {
      if (ref.mounted) state = SaveState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = const SaveState(
          error:
              'Data belum tersimpan. Periksa ruang penyimpanan lalu coba lagi.',
        );
      }
    }
    return false;
  }
}
