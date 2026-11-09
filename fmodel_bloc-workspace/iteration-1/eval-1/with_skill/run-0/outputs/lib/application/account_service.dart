/// Thin application-layer facade the presentation layer depends on.
///
/// This IS part of the deliverable: it is the single collaborator the
/// `TransferBloc` is injected with. It never exposes the aggregate, the
/// `Decider`, or any repository directly to presentation code — only two
/// use-case-shaped methods: "run a transfer" (write side) and "read an
/// account" (query side). See NAMING-AND-LAYERS.md, section 5, for why this
/// indirection matters: it is what lets `TransferBloc` be constructed with a
/// fake in tests, and what keeps the aggregate/repository construction out
/// of presentation code entirely.
library;

import 'package:fmodel/application.dart';

import '../domain/account_view_api.dart';
import '../domain/transfer_money_api.dart';
import 'account_view_repository.dart';

class AccountService {
  AccountService(this._aggregate, this._accountViewRepository);

  /// Owned by fmodel / the upstream skill: `createEventSourcingAggregate`
  /// wired with the `transferMoneyDecider()` and an `EventRepository`
  /// adapter over the real event store. `AccountService` never constructs
  /// this itself — it is handed one through the constructor.
  final EventSourcingAggregate<
    TransferMoneyCommand,
    AccountState,
    LedgerEvent,
    NoMetadata,
    NoMetadata
  >
  _aggregate;

  /// Query-side port; see `account_view_repository.dart`.
  final AccountViewRepository _accountViewRepository;

  /// Runs one transfer: `fetchEvents -> decide -> save`, all inside
  /// `_aggregate.handle`. Throws a [DomainError] if the Decider rejects the
  /// command (e.g. [InsufficientFundsError]); resolves once the resulting
  /// [LedgerEvent]s are durably saved otherwise.
  ///
  /// Deliberately returns `Future<void>`, not the emitted `LedgerEvent`s —
  /// the presentation layer reads results back from the query side
  /// (`account`, below), never from the write side's event stream. Keeping
  /// this boundary narrow is what stops a `LedgerEvent` from ever leaking
  /// into `TransferBloc`.
  Future<void> transfer(TransferMoneyCommand command) =>
      _aggregate.handle(command).drain<void>();

  /// Reads the current [AccountViewState] projection for [accountId] from
  /// the query side. This — not `AccountState`, the Decider's write-model —
  /// is what `TransferUiState` is built from.
  Future<AccountViewState> account(String accountId) =>
      _accountViewRepository.fetchByAccountId(accountId);
}
