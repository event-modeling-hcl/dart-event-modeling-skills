/// Read-model (query-side) type for the account screen.
///
/// ---------------------------------------------------------------------
/// NOT PART OF THIS SKILL'S DELIVERABLE — see the note at the top of
/// `transfer_money_api.dart`. `AccountViewState` is what a `View`/
/// `MaterializedView` folds [LedgerEvent]s into on the query side; it is
/// owned by fmodel / the upstream skill and only imported here.
///
/// This is the type `TransferUiState` renders from — never `AccountState`,
/// the write-model in `transfer_money_api.dart`. Keeping the UI on the read
/// side is what makes "Bloc State != Aggregate/Decider State" true in code,
/// not just in principle.
/// ---------------------------------------------------------------------
library;

import 'package:equatable/equatable.dart';

/// Query-side projection of one account, folded from [LedgerEvent]s.
final class AccountViewState extends Equatable {
  const AccountViewState({
    required this.accountId,
    required this.balanceCents,
    this.recentTransferIds = const [],
  });

  final String accountId;
  final int balanceCents;

  /// Most recent settled transfer ids touching this account, newest first.
  final List<String> recentTransferIds;

  @override
  List<Object?> get props => [accountId, balanceCents, recentTransferIds];
}
