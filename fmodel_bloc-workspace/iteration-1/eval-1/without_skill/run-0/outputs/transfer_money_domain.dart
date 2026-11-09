/// Write-model domain layer for the "transfer money" feature.
///
/// This file is **not part of the deliverable** — it is the fmodel-dart
/// `Decider<TransferMoneyCommand, AccountState, LedgerEvent>` and its event
/// repository, stubbed out just enough to make the Bloc example in this
/// directory compile and analyze on its own. In a real app this already
/// exists in your domain/application layers; nothing here should be copied
/// wholesale.
///
/// Naming note: every type in this file that represents a *domain fact*
/// (something the decider decided actually happened to the ledger) is a
/// [LedgerEvent]. Nothing in this file is ever called a bare "Event" — that
/// word is reserved, throughout this example, for the Bloc's UI-facing
/// input type (`TransferUiEvent`, defined in `transfer_ui_event.dart`).
library;

import 'package:fmodel/domain.dart';
import 'package:fmodel/application.dart';

// ---------------------------------------------------------------------------
// Command (write side, input to the decider)
// ---------------------------------------------------------------------------

/// Intent to move money from one account to another.
///
/// [requestId] is a client-generated idempotency key: since the Bloc will
/// serialize submissions with `sequential()`, each accepted UI submission
/// produces exactly one command with its own id, which is useful for
/// de-duplicating retries at the repository/storage boundary.
final class TransferMoneyCommand {
  const TransferMoneyCommand({
    required this.requestId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinorUnits,
    required this.currency,
  });

  final String requestId;
  final String fromAccountId;
  final String toAccountId;
  final int amountMinorUnits;
  final String currency;
}

// ---------------------------------------------------------------------------
// State (write side, folded by the decider — never shown directly in the UI)
// ---------------------------------------------------------------------------

final class AccountState {
  const AccountState({required this.balancesMinorUnits});

  factory AccountState.initial() => const AccountState(balancesMinorUnits: {});

  /// accountId -> balance in minor units (e.g. cents).
  final Map<String, int> balancesMinorUnits;

  int balanceOf(String accountId) => balancesMinorUnits[accountId] ?? 0;

  AccountState withBalance(String accountId, int balance) => AccountState(
    balancesMinorUnits: {...balancesMinorUnits, accountId: balance},
  );
}

// ---------------------------------------------------------------------------
// LedgerEvent — the domain fact. This is deliberately NOT named "Event" or
// "DomainEvent": in this codebase "Event" is reserved for Bloc's UI-facing
// input, and collapsing the two names is exactly the confusion this example
// is designed to avoid.
// ---------------------------------------------------------------------------

sealed class LedgerEvent {
  const LedgerEvent();
}

final class MoneyTransferred extends LedgerEvent {
  const MoneyTransferred({
    required this.transferId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinorUnits,
    required this.currency,
    required this.occurredAt,
  });

  final String transferId;
  final String fromAccountId;
  final String toAccountId;
  final int amountMinorUnits;
  final String currency;
  final DateTime occurredAt;
}

final class TransferRejected extends LedgerEvent {
  const TransferRejected({required this.requestId, required this.reason});

  final String requestId;
  final String reason;
}

// ---------------------------------------------------------------------------
// Decider — pure decision + evolution logic
// ---------------------------------------------------------------------------

Decider<TransferMoneyCommand, AccountState, LedgerEvent>
buildTransferMoneyDecider() {
  return Decider<TransferMoneyCommand, AccountState, LedgerEvent>(
    initialState: AccountState.initial(),
    decide: (command, state) async* {
      final available = state.balanceOf(command.fromAccountId);
      if (available < command.amountMinorUnits) {
        yield TransferRejected(
          requestId: command.requestId,
          reason: 'insufficient_funds',
        );
        return;
      }

      yield MoneyTransferred(
        transferId: command.requestId,
        fromAccountId: command.fromAccountId,
        toAccountId: command.toAccountId,
        amountMinorUnits: command.amountMinorUnits,
        currency: command.currency,
        occurredAt: DateTime.now().toUtc(),
      );
    },
    evolve: (state, event) => switch (event) {
      MoneyTransferred() => state
          .withBalance(
            event.fromAccountId,
            state.balanceOf(event.fromAccountId) - event.amountMinorUnits,
          )
          .withBalance(
            event.toAccountId,
            state.balanceOf(event.toAccountId) + event.amountMinorUnits,
          ),
      TransferRejected() => state,
    },
  );
}

// ---------------------------------------------------------------------------
// Event repository — in-memory stand-in for whatever event store you use.
// ---------------------------------------------------------------------------

final class InMemoryTransferEventRepository
    with EventRepositoryDefaults<TransferMoneyCommand, LedgerEvent>
    implements
        EventRepository<
          TransferMoneyCommand,
          LedgerEvent,
          NoMetadata,
          NoMetadata
        > {
  final List<LedgerEvent> _stream = [];

  @override
  Stream<LedgerEvent> fetchEvents(TransferMoneyCommand command) =>
      Stream.fromIterable(
        _stream.where(
          (e) =>
              (e is MoneyTransferred &&
                  (e.fromAccountId == command.fromAccountId ||
                      e.toAccountId == command.fromAccountId)) ||
              e is TransferRejected,
        ),
      );

  @override
  Stream<LedgerEvent> save(Stream<LedgerEvent> events) async* {
    await for (final event in events) {
      _stream.add(event);
      yield event;
    }
  }
}

/// Alias so the application layer doesn't have to spell out fmodel's two
/// metadata type parameters (`CM`, `EM`) everywhere it names the aggregate.
/// This app doesn't use per-command/per-event metadata, so both are
/// [NoMetadata] — fmodel's own marker type for "no metadata here".
typedef TransferMoneyAggregate =
    EventSourcingAggregate<
      TransferMoneyCommand,
      AccountState,
      LedgerEvent,
      NoMetadata,
      NoMetadata
    >;

TransferMoneyAggregate buildTransferMoneyAggregate({
  required EventRepository<
    TransferMoneyCommand,
    LedgerEvent,
    NoMetadata,
    NoMetadata
  >
  eventRepository,
}) {
  return createEventSourcingAggregate<
    TransferMoneyCommand,
    AccountState,
    LedgerEvent,
    NoMetadata,
    NoMetadata
  >(decider: buildTransferMoneyDecider(), eventRepository: eventRepository);
}
