/// The Bloc for the transfer-money screen.
///
/// Reads: [TransferUiEvent] in, [TransferUiState] out (both `Ui`-marked, see
/// their own files). The only domain type this file ever names is
/// `TransferMoneyCommand` — it is built here and handed to the injected
/// service; `LedgerEvent` is never constructed or emitted by this class.
library;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import 'transfer_money_service.dart';
import 'transfer_ui_event.dart';
import 'transfer_ui_state.dart';

class TransferBloc extends Bloc<TransferUiEvent, TransferUiState> {
  /// The service is injected, not constructed here — callers wire up the
  /// decider, event repository, and aggregate once (see
  /// `transfer_feature.dart`) and hand this Bloc a ready-to-use
  /// [TransferMoneyService]. That keeps this class trivially testable with
  /// `bloc_test` against a fake/mock service, and means this screen's
  /// lifecycle is decoupled from the aggregate's.
  TransferBloc({required TransferMoneyService transferMoneyService})
    : _transferMoneyService = transferMoneyService,
      super(const TransferUiState()) {
    // `sequential()` is the load-bearing choice here. TransferSubmitted
    // triggers a full fetch -> decide -> save cycle against this account's
    // event stream. If two submissions were allowed to run concurrently
    // (the Bloc default) or to cancel each other (`restartable()`) or to
    // silently drop the second tap (`droppable()`), two in-flight handlers
    // could both fetch the *same* current event stream, both decide
    // against it, and both append — a classic lost-update race on the
    // aggregate. `sequential()` queues TransferSubmitted events and runs
    // them strictly one at a time, in arrival order, so every submission
    // sees the effects of the one before it. This is what actually gives
    // the "cannot let two commands race against the same account's event
    // stream" requirement its guarantee — the transformer, not just using
    // Bloc-over-Cubit, is what provides it.
    on<TransferSubmitted>(_onTransferSubmitted, transformer: sequential());

    // This UI event acknowledges a banner and touches no shared resource,
    // so it uses the Bloc's default (concurrent) processing — there is
    // nothing here that needs to queue behind anything else.
    on<TransferResultAcknowledged>(_onTransferResultAcknowledged);
  }

  final TransferMoneyService _transferMoneyService;

  @override
  void onEvent(TransferUiEvent event) {
    // Every TransferUiEvent — successful, rejected, or merely acknowledged
    // — passes through here before its handler runs, in the exact order
    // add() was called. Point a BlocObserver (or this override) at your
    // logging/analytics sink and you have an auditable stream of what the
    // user did, independent of what the write model decided to do about
    // it. See `AuditingBlocObserver` in `transfer_feature.dart` for the
    // app-wide version of this same hook.
    super.onEvent(event);
  }

  Future<void> _onTransferSubmitted(
    TransferSubmitted event,
    Emitter<TransferUiState> emit,
  ) async {
    emit(state.copyWith(status: TransferUiStatus.submitting, clearError: true));

    try {
      // UI action -> fmodel command, handled entirely inside the service.
      // This handler never sees a LedgerEvent and never builds one itself.
      final historyEntry = await _transferMoneyService.transfer(
        fromAccountId: event.fromAccountId,
        toAccountId: event.toAccountId,
        amountMinorUnits: event.amountMinorUnits,
        currency: event.currency,
      );

      emit(
        state.copyWith(
          status: TransferUiStatus.success,
          history: [historyEntry, ...state.history],
        ),
      );
    } on TransferRejectedException catch (e) {
      emit(
        state.copyWith(status: TransferUiStatus.failure, errorMessage: e.message),
      );
    }
  }

  void _onTransferResultAcknowledged(
    TransferResultAcknowledged event,
    Emitter<TransferUiState> emit,
  ) {
    emit(state.copyWith(status: TransferUiStatus.idle, clearError: true));
  }
}
