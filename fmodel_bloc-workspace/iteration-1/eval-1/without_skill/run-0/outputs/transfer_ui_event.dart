/// UI-facing inputs to [TransferBloc].
///
/// Naming convention used throughout this feature: anything the *user*
/// does is a [TransferUiEvent] — note the explicit `Ui` marker. It is never
/// called a bare "Event" or "TransferEvent", because this codebase already
/// has a domain type with that shape of name: `LedgerEvent`
/// (see `transfer_money_domain.dart`), which is the fmodel-dart decider's
/// output — a fact the write model decided actually happened.
///
/// `TransferUiEvent` and `LedgerEvent` are unrelated types on purpose:
/// - `TransferUiEvent` = "the user asked for X" (intent, always named as a
///   past-tense action the user took, e.g. `TransferSubmitted`).
/// - `LedgerEvent` = "the ledger recorded Y" (domain fact, produced by
///   `Decider.decide`).
///
/// Bloc's own generic parameter is literally called `Event` (`Bloc<Event,
/// State>`), which is what makes it so easy to reach for the word "event"
/// here and mean the wrong one. Importing this file as `ui_event` and the
/// domain file as `domain` (or similar) at call sites, and never importing
/// both without a prefix, is the cheapest guardrail against that mix-up.
library;

import 'package:equatable/equatable.dart';

/// Sealed root of every UI-facing input this screen can receive.
///
/// Sealed + [Equatable] gives us exhaustive `switch` handling wherever this
/// type is consumed, and value equality for tests (`blocTest` compares
/// events/states by `==`).
sealed class TransferUiEvent extends Equatable {
  const TransferUiEvent();

  @override
  List<Object?> get props => [];
}

/// The user tapped "Send" on the transfer form.
///
/// This is the one UI event that must never overlap with another instance
/// of itself for the same account — see `transfer_bloc.dart` for how
/// `sequential()` enforces that.
final class TransferSubmitted extends TransferUiEvent {
  const TransferSubmitted({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinorUnits,
    required this.currency,
  });

  final String fromAccountId;
  final String toAccountId;
  final int amountMinorUnits;
  final String currency;

  @override
  List<Object?> get props => [
    fromAccountId,
    toAccountId,
    amountMinorUnits,
    currency,
  ];
}

/// The user dismissed the success/error banner from the last submission
/// (e.g. tapped "OK" on a snackbar, or navigated back to the idle form).
///
/// Deliberately registered without `sequential()` in the Bloc: it touches
/// no shared resource and has nothing to queue behind, so the extra
/// ordering guarantee would only add latency for no safety benefit.
final class TransferResultAcknowledged extends TransferUiEvent {
  const TransferResultAcknowledged();
}
