import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

// Domain + application, owned by the fmodel layer — imported, never
// redefined. Only `AccountService` and `AccountViewState` are actually used
// by this Bloc; `AccountState` and `LedgerEvent` are imported solely so the
// doc comments below can refer to them by name.
import '../../application/account_service.dart';
import '../../domain/account_view_api.dart';
import '../../domain/transfer_money_api.dart';

part 'transfer_ui_event.dart';
part 'transfer_ui_state.dart';

/// Presentation logic for the Transfer Money screen.
///
/// Why a Bloc and not a Cubit: [TransferSubmitted] issues a
/// [TransferMoneyCommand] against an event-sourced aggregate keyed by
/// [accountId]. If the user fires "transfer" twice in quick succession,
/// two overlapping handler runs would each do their own
/// fetch-events -> decide -> save cycle against the *same* account stream —
/// the second `save` can race the first, corrupting the ledger or silently
/// dropping a transfer. A Cubit method call has no built-in way to prevent
/// that overlap; a Bloc does, via an `EventTransformer` passed to `on<E>`.
/// Registering [_onTransferSubmitted] with `transformer: sequential()`
/// makes the event handler process every `TransferSubmitted` strictly one
/// at a time, in arrival order — the next transfer's handler cannot start
/// until the previous one's `save` has completed. That is the whole
/// concurrency-control requirement, enforced at the framework level instead
/// of with a hand-rolled mutex. As a side benefit, every `add(event)` is
/// now a discrete, typed, loggable fact about what the user asked for —
/// attach a `BlocObserver.onEvent` (see `transfer_di.dart`) for a full
/// audit trail of user-initiated transfers, independent of the ledger's own
/// event log.
class TransferBloc extends Bloc<TransferUiEvent, TransferUiState> {
  TransferBloc(this._accountService, {required String accountId})
    : _accountId = accountId,
      super(const TransferUiState.initial()) {
    // Exactly one handler per concrete UiEvent type — `on<E>` dispatches by
    // concrete runtime type, so registering the sealed base would silently
    // receive nothing.
    //
    // `sequential()` on the command-issuing handler: two `TransferSubmitted`
    // events in flight are queued and run one at a time, so they can never
    // race the same account's fetch/decide/save cycle. This is the
    // transformer the "no two commands racing the same stream" requirement
    // needs — `concurrent()` (the default) would reintroduce the race,
    // `droppable()` would silently swallow the second tap instead of
    // queuing it, and `restartable()` would cancel an in-flight transfer
    // outright, which is never safe for a write.
    on<TransferSubmitted>(_onTransferSubmitted, transformer: sequential());
    // `restartable()` on the query-only handler: it is always safe to
    // cancel a stale account-overview read in favor of a fresher one, since
    // reads have no side effects to race.
    on<AccountOverviewRequested>(
      _onAccountOverviewRequested,
      transformer: restartable(),
    );
  }

  final AccountService _accountService;
  final String _accountId;

  Future<void> _onTransferSubmitted(
    TransferSubmitted event,
    Emitter<TransferUiState> emit,
  ) async {
    emit(state.copyWith(status: TransferStatus.loading));
    try {
      // 1-2: UI intent -> fmodel Command. Never construct
      // MoneyDebitedEvent/MoneyCreditedEvent here; the aggregate's Decider
      // alone decides which domain events, if any, result.
      final command = TransferMoneyCommand(
        fromAccountId: event.fromAccountId,
        toAccountId: event.toAccountId,
        amountCents: event.amountCents,
      );
      // 3: application layer runs fetch -> decide -> evolve -> save. Because
      // this handler is registered with `sequential()`, no other
      // TransferSubmitted can enter this block concurrently.
      await _accountService.transfer(command);
      // 4: read fresh render data from the query side — never the Decider's
      // AccountState.
      final account = await _accountService.account(_accountId);
      // 5: emit a UiState built from the read model, never the write model.
      emit(state.copyWith(status: TransferStatus.success, account: account));
    } on DomainError catch (e) {
      emit(state.copyWith(status: TransferStatus.failure, error: e.message));
    }
  }

  Future<void> _onAccountOverviewRequested(
    AccountOverviewRequested event,
    Emitter<TransferUiState> emit,
  ) async {
    emit(state.copyWith(status: TransferStatus.loading));
    try {
      final account = await _accountService.account(_accountId);
      emit(state.copyWith(status: TransferStatus.success, account: account));
    } on DomainError catch (e) {
      emit(state.copyWith(status: TransferStatus.failure, error: e.message));
    }
  }
}
