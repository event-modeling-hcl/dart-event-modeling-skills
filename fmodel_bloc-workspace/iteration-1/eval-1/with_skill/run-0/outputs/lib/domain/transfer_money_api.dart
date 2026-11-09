/// Domain layer for the "transfer money" use case.
///
/// ---------------------------------------------------------------------
/// NOT PART OF THIS SKILL'S DELIVERABLE.
///
/// In your real project this file (the `Decider<TransferMoneyCommand,
/// AccountState, LedgerEvent>`, its commands, its domain events, and its
/// errors) already exists — it is owned by fmodel-dart and, upstream, by the
/// `map-event-model-hcl-to-code` skill. `fmodel_bloc` never redefines or
/// renames domain types; it only imports them.
///
/// It is included in this sample, verbatim-minimal, purely so that the
/// presentation-layer files this skill *does* own (`lib/presentation/...`)
/// form a package that `dart analyze` can actually resolve and check.
/// Treat everything below as "assumed to already exist" — the interesting
/// code for this task is in `lib/presentation/transfer/`.
/// ---------------------------------------------------------------------
library;

import 'package:equatable/equatable.dart';
import 'package:fmodel/domain.dart';

/// Intent to move money from one account to another. Input to `decide`.
final class TransferMoneyCommand extends Equatable {
  const TransferMoneyCommand({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountCents,
  });

  final String fromAccountId;
  final String toAccountId;
  final int amountCents;

  @override
  List<Object?> get props => [fromAccountId, toAccountId, amountCents];
}

/// Sealed base for every fact the ledger Decider can emit. A **domain**
/// event — a fact that already happened — never to be confused with a bloc
/// `UiEvent`, which is a UI *intent* (see `transfer_ui_event.dart`).
sealed class LedgerEvent extends Equatable {
  const LedgerEvent({required this.transferId});

  final String transferId;
}

/// Fact: funds were debited from the source account.
final class MoneyDebitedEvent extends LedgerEvent {
  const MoneyDebitedEvent({
    required super.transferId,
    required this.accountId,
    required this.amountCents,
  });

  final String accountId;
  final int amountCents;

  @override
  List<Object?> get props => [transferId, accountId, amountCents];
}

/// Fact: funds were credited to the destination account.
final class MoneyCreditedEvent extends LedgerEvent {
  const MoneyCreditedEvent({
    required super.transferId,
    required this.accountId,
    required this.amountCents,
  });

  final String accountId;
  final int amountCents;

  @override
  List<Object?> get props => [transferId, accountId, amountCents];
}

/// Sealed base for domain rule violations `decide` can reject a command
/// with. Thrown by the aggregate, caught by the Bloc handler.
sealed class DomainError extends Equatable implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class InsufficientFundsError extends DomainError {
  const InsufficientFundsError(String accountId)
    : super('Account $accountId does not have sufficient funds.');
}

final class AccountNotFoundError extends DomainError {
  const AccountNotFoundError(String accountId)
    : super('Account $accountId was not found.');
}

/// Write-model state, folded from [LedgerEvent]s by `evolve`. Internal to
/// the command side — the presentation layer must never render this
/// directly; see `AccountViewState` in `account_view_api.dart` instead.
final class AccountState extends Equatable {
  const AccountState({required this.accountId, required this.balanceCents});

  final String accountId;
  final int balanceCents;

  @override
  List<Object?> get props => [accountId, balanceCents];
}

/// The pure decider. Shown only so the sample type-checks against
/// `package:fmodel/domain.dart`'s `Decider<C, S, E>` shape; the real
/// implementation (and its given/when/then tests) belongs to the
/// upstream skill's output, not to `fmodel_bloc`.
Decider<TransferMoneyCommand, AccountState, LedgerEvent>
transferMoneyDecider() => Decider<TransferMoneyCommand, AccountState, LedgerEvent>(
  decide: (command, state) async* {
    if (state.balanceCents < command.amountCents) {
      throw InsufficientFundsError(command.fromAccountId);
    }
    final transferId =
        '${command.fromAccountId}-${command.toAccountId}-${command.amountCents}';
    yield MoneyDebitedEvent(
      transferId: transferId,
      accountId: command.fromAccountId,
      amountCents: command.amountCents,
    );
    yield MoneyCreditedEvent(
      transferId: transferId,
      accountId: command.toAccountId,
      amountCents: command.amountCents,
    );
  },
  evolve: (state, event) => switch (event) {
    MoneyDebitedEvent() => AccountState(
      accountId: state.accountId,
      balanceCents: state.balanceCents - event.amountCents,
    ),
    MoneyCreditedEvent() => AccountState(
      accountId: state.accountId,
      balanceCents: state.balanceCents + event.amountCents,
    ),
  },
  initialState: const AccountState(accountId: '', balanceCents: 0),
);
