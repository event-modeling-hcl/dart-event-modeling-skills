part of 'transfer_bloc.dart';

/// Status of the last UI intent handled by [TransferBloc].
enum TransferStatus { initial, loading, success, failure }

/// What the Transfer Money screen renders.
///
/// `TransferUiState` is built from the **read side** —
/// [AccountViewState], a query-side projection — plus a status. It is
/// never built from [AccountState], the Decider's write-model; that
/// boundary is what makes "Bloc State != Aggregate State" true in code,
/// not just in principle. `Equatable` gives it the value equality `emit`
/// relies on to de-dupe identical states.
final class TransferUiState extends Equatable {
  const TransferUiState({
    this.status = TransferStatus.initial,
    this.account,
    this.error,
  });

  const TransferUiState.initial() : this();

  final TransferStatus status;

  /// Read-model projection for the account this screen is showing — never
  /// the Decider's `AccountState`.
  final AccountViewState? account;

  /// Human-readable message surfaced from a [DomainError], if the last
  /// [TransferSubmitted] was rejected.
  final String? error;

  TransferUiState copyWith({
    TransferStatus? status,
    AccountViewState? account,
    String? error,
  }) => TransferUiState(
    status: status ?? this.status,
    account: account ?? this.account,
    // Explicit clear: a fresh success/loading transition should drop a
    // stale error message rather than inherit it via `??`.
    error: error,
  );

  @override
  List<Object?> get props => [status, account, error];
}
