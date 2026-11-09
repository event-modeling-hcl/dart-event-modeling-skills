/// Application service that sits between [TransferBloc] and the fmodel-dart
/// write model.
///
/// This is the *only* place that is allowed to construct a
/// `TransferMoneyCommand` and the *only* place that reads `LedgerEvent`
/// values coming back out of `TransferMoneyAggregate.handle`. The Bloc
/// itself never touches either type directly — it calls [transfer] and
/// gets back either a [TransferHistoryEntry] (read-side data, safe to put
/// straight into `TransferUiState`) or a [TransferRejectedException].
library;

import 'dart:math';

import 'transfer_money_domain.dart';
import 'transfer_ui_state.dart';

/// Generates a request id for a new [TransferMoneyCommand].
///
/// Kept as a simple injectable function rather than pulling in `package:uuid`
/// so this example has no dependencies beyond bloc/fmodel. Swap in a real
/// UUID generator (or anything else your event store expects as an
/// idempotency key) in production.
typedef IdGenerator = String Function();

String _defaultIdGenerator() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Thrown when the decider rejected the command (e.g. insufficient funds).
/// A domain-level failure, not a bug — the Bloc catches this specifically
/// and turns it into [TransferUiStatus.failure] instead of letting it
/// escape as an unhandled error.
final class TransferRejectedException implements Exception {
  const TransferRejectedException(this.message);

  final String message;

  @override
  String toString() => 'TransferRejectedException: $message';
}

class TransferMoneyService {
  TransferMoneyService({
    required TransferMoneyAggregate transferMoneyAggregate,
    IdGenerator idGenerator = _defaultIdGenerator,
  }) : _transferMoneyAggregate = transferMoneyAggregate,
       _idGenerator = idGenerator;

  final TransferMoneyAggregate _transferMoneyAggregate;
  final IdGenerator _idGenerator;

  /// Turns a UI-level transfer request into a [TransferMoneyCommand],
  /// dispatches it to the aggregate (fetch → decide → save, all inside
  /// `handle`), and maps the resulting `LedgerEvent`s into UI-safe data.
  ///
  /// Callers (the Bloc) must serialize calls to this method per account —
  /// this method itself does not; see `transfer_bloc.dart`'s use of
  /// `sequential()` for where that guarantee actually lives.
  Future<TransferHistoryEntry> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinorUnits,
    required String currency,
  }) async {
    final command = TransferMoneyCommand(
      requestId: _idGenerator(),
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountMinorUnits: amountMinorUnits,
      currency: currency,
    );

    final savedEvents = await _transferMoneyAggregate.handle(command).toList();

    for (final event in savedEvents) {
      if (event is TransferRejected) {
        throw TransferRejectedException(event.reason);
      }
    }

    final completed = savedEvents.whereType<MoneyTransferred>().single;

    return TransferHistoryEntry(
      id: completed.transferId,
      fromAccountId: completed.fromAccountId,
      toAccountId: completed.toAccountId,
      amountMinorUnits: completed.amountMinorUnits,
      currency: completed.currency,
      occurredAt: completed.occurredAt,
    );
  }
}
