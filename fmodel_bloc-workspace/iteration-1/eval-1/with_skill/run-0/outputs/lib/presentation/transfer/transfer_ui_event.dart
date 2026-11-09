part of 'transfer_bloc.dart';

/// UI intents for the Transfer Money screen.
///
/// A `TransferUiEvent` is **never** a domain event. It is a request the
/// user (or the screen) is making — the `Ui` marker exists precisely so it
/// can never be confused with [LedgerEvent], the sealed base of the facts
/// the ledger `Decider` actually emits (`MoneyDebitedEvent`,
/// `MoneyCreditedEvent`). `TransferBloc` never constructs, emits, or
/// registers an `on<LedgerEvent>` handler — only `on<TransferUiEvent>`
/// cases, below.
sealed class TransferUiEvent extends Equatable {
  const TransferUiEvent();

  @override
  List<Object?> get props => [];
}

/// The user tapped "Send" on the transfer form. Maps to a
/// [TransferMoneyCommand] inside [TransferBloc._onTransferSubmitted] — it
/// does NOT map to `MoneyDebitedEvent`/`MoneyCreditedEvent`. Whether either
/// of those domain events results is entirely up to the Decider.
final class TransferSubmitted extends TransferUiEvent {
  const TransferSubmitted({
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

/// The screen wants the current account projection (initial load or
/// pull-to-refresh). Maps to a query against the read side, not a command —
/// see `restartable()` in `transfer_bloc.dart` for why this case does not
/// need `sequential()`.
final class AccountOverviewRequested extends TransferUiEvent {
  const AccountOverviewRequested();
}
