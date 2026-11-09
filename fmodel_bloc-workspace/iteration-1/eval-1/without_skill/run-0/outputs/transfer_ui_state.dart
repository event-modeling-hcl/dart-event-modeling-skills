/// UI-facing output of [TransferBloc].
///
/// Naming convention: this is [TransferUiState] — the `Ui` marker mirrors
/// [TransferUiEvent] (see `transfer_ui_event.dart`) and, deliberately, this
/// type is *not* the write-model `AccountState` that the fmodel-dart
/// decider folds events into. `AccountState` is private to the write side;
/// the screen never renders it directly. What the screen renders comes from
/// [TransferHistoryEntry] values that the application service hands back
/// after a command has been successfully applied — i.e. read-side data,
/// even though in this simplified example it's read straight off the
/// command result rather than a separately-projected read model.
library;

import 'package:equatable/equatable.dart';

enum TransferUiStatus { idle, submitting, success, failure }

/// A single completed transfer, shaped for display — an id, the two
/// accounts, the amount, and when it happened. This is intentionally a
/// small DTO distinct from any domain type: the write model's
/// `MoneyTransferred` (a `LedgerEvent`) is mapped into this by the
/// application service (see `transfer_money_service.dart`) before it ever
/// reaches the Bloc.
final class TransferHistoryEntry extends Equatable {
  const TransferHistoryEntry({
    required this.id,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinorUnits,
    required this.currency,
    required this.occurredAt,
  });

  final String id;
  final String fromAccountId;
  final String toAccountId;
  final int amountMinorUnits;
  final String currency;
  final DateTime occurredAt;

  @override
  List<Object?> get props => [
    id,
    fromAccountId,
    toAccountId,
    amountMinorUnits,
    currency,
    occurredAt,
  ];
}

final class TransferUiState extends Equatable {
  const TransferUiState({
    this.status = TransferUiStatus.idle,
    this.history = const [],
    this.errorMessage,
  });

  final TransferUiStatus status;

  /// Most-recent-first. Populated from the read side (via the application
  /// service's return value), never from `AccountState`.
  final List<TransferHistoryEntry> history;

  /// Set only when [status] is [TransferUiStatus.failure].
  final String? errorMessage;

  bool get isSubmitting => status == TransferUiStatus.submitting;

  TransferUiState copyWith({
    TransferUiStatus? status,
    List<TransferHistoryEntry>? history,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TransferUiState(
      status: status ?? this.status,
      history: history ?? this.history,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, history, errorMessage];
}
