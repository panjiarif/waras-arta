import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/finance.dart';
import '../../../domain/finance_repository.dart';
import 'ledger_view_model.dart';

final accountDetailsProvider = StreamProvider.autoDispose
    .family<AccountDetails?, int>((ref, accountId) {
      return ref
          .watch(financeRepositoryProvider)
          .watchAccountDetails(accountId);
    });

enum AccountOperation { update, adjustBalance, archive, restore, delete }

class AccountActionState {
  const AccountActionState({this.operation, this.targetId, this.error});

  final AccountOperation? operation;
  final int? targetId;
  final String? error;

  bool get isSaving => operation != null;
}

final accountActionsProvider =
    NotifierProvider<AccountActions, AccountActionState>(AccountActions.new);

class AccountActions extends Notifier<AccountActionState> {
  @override
  AccountActionState build() => const AccountActionState();

  Future<bool> updateAccount(int id, AccountUpdateDraft draft) => _run(
    operation: AccountOperation.update,
    targetId: id,
    action: (repository) => repository.updateAccount(id, draft),
  );

  Future<bool> adjustBalance(int id, AccountBalanceAdjustmentDraft draft) =>
      _run(
        operation: AccountOperation.adjustBalance,
        targetId: id,
        occurredAt: draft.occurredAt,
        action: (repository) async {
          await repository.adjustAccountBalance(id, draft);
        },
      );

  Future<bool> setArchived(int id, bool archived) => _run(
    operation: archived ? AccountOperation.archive : AccountOperation.restore,
    targetId: id,
    action: (repository) => repository.setAccountArchived(id, archived),
  );

  Future<bool> deleteAccount(int id) => _run(
    operation: AccountOperation.delete,
    targetId: id,
    action: (repository) => repository.deleteAccount(id),
  );

  void clearError() {
    if (!state.isSaving && state.error != null) {
      state = const AccountActionState();
    }
  }

  Future<bool> _run({
    required AccountOperation operation,
    required int targetId,
    required Future<void> Function(FinanceRepository repository) action,
    DateTime? occurredAt,
  }) async {
    if (state.isSaving) return false;
    state = AccountActionState(operation: operation, targetId: targetId);
    try {
      await action(ref.read(financeRepositoryProvider));
      if (!ref.mounted) return true;
      if (occurredAt != null) {
        ref.read(ledgerFilterProvider.notifier).showMonth(occurredAt);
      }
      state = const AccountActionState();
      return true;
    } on FinanceValidationException catch (error) {
      if (ref.mounted) {
        state = AccountActionState(targetId: targetId, error: error.message);
      }
    } catch (_) {
      if (ref.mounted) {
        state = AccountActionState(
          targetId: targetId,
          error: 'Rekening belum diubah. Coba lagi beberapa saat lagi.',
        );
      }
    }
    return false;
  }
}
