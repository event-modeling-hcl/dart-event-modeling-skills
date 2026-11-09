# Transfer Money screen: Bloc over your `TransferMoneyCommand` decider

Your instinct is right on both counts: use a **Bloc**, not a Cubit, and use
`bloc_concurrency`'s **`sequential()`** transformer on the handler that issues
the command. Here's the shape, and why each piece is named the way it is.

## Why Bloc, not Cubit

A Cubit method call *is* its own dispatch — there's no queue in front of it.
If the user taps "transfer" twice fast, you'd get two overlapping calls to
your method, each running its own `fetchEvents → decide → save` cycle
against the *same* account's event stream, with no ordering guarantee
between them. That's exactly the race you said you can't allow.

A Bloc's `on<E>(handler, transformer: ...)` puts an `EventTransformer` in
front of the handler. `sequential()` processes every event of that type
strictly one at a time, in arrival order — the next `TransferSubmitted`
cannot start until the previous one's `save` has completed. That's
concurrency control enforced by the framework, not a hand-rolled mutex.
You also get the audit stream for free: every `add(TransferSubmitted(...))`
is a discrete, typed, timestamped fact about what the user asked for, which
`BlocObserver.onEvent` can capture globally (see `TransferAuditObserver` in
`transfer_di.dart`).

## Why `sequential()` and not the other transformers

| Transformer | What it does here |
| --- | --- |
| `concurrent()` (the default) | Runs every `TransferSubmitted` in parallel — this is the exact race you're trying to prevent. Never leave a command handler on this. |
| `droppable()` | Runs the first submit, silently ignores taps while it's in flight. Prevents the race but **silently drops** transfers the user asked for — wrong for money. |
| `restartable()` | Cancels the in-flight handler when a new event arrives. Fine for a search box; **never** safe for a write — it would abandon a transfer mid-`save`. |
| `sequential()` | Queues every `TransferSubmitted` and runs them one at a time, in order. Nothing races, nothing is silently dropped, nothing is cancelled mid-write. |

`sequential()` is the only one of the four that satisfies "processed
strictly one at a time, in order" without also silently losing a user's
tap. It's used only on the command-issuing handler (`TransferSubmitted`);
the account-overview query handler is registered with `restartable()`
instead, because discarding a stale *read* is always safe — there's nothing
to lose by cancelling a read in favor of a fresher one.

## Naming: keeping "event" straight

This stack has two completely different things both called "event," and the
fix is a single marker, applied consistently:

| Type | Layer | Meaning |
| --- | --- | --- |
| `LedgerEvent` (and `MoneyDebitedEvent`, `MoneyCreditedEvent`) | **domain** | A fact the `Decider` already emitted. Output of `decide`, input to `evolve`. |
| `TransferUiEvent` (and `TransferSubmitted`, `AccountOverviewRequested`) | **presentation** | A UI *intent* — a request the user made. Input to a Bloc handler. |

`TransferBloc` never constructs, emits, or registers a handler for a
`LedgerEvent`. It only ever deals in `TransferUiEvent`s on the way in and
`TransferUiState` on the way out. The same discipline applies to state:
`TransferUiState` is built from `AccountViewState` — the **read-side**
projection — never from `AccountState`, the Decider's write-model. That's
what keeps "Bloc State ≠ Aggregate State" true in the code, not just as a
principle you have to remember.

## The files

- `lib/domain/transfer_money_api.dart`, `lib/domain/account_view_api.dart` —
  **not this task's deliverable.** These stand in for the domain layer you
  already have (`TransferMoneyCommand`, `LedgerEvent`, `AccountState`,
  `DomainError`, `AccountViewState`). They're included only so this sample
  is self-contained and `dart analyze`/`flutter pub get` actually pass end
  to end — in your real project, `fmodel_bloc` imports these, it never
  redefines them.
- `lib/application/account_service.dart`,
  `lib/application/account_view_repository.dart` — the thin service
  `TransferBloc` depends on. `AccountService.transfer` wraps
  `EventSourcingAggregate.handle` (fetch → decide → save); `AccountService.account`
  reads the fresh `AccountViewState` projection. `TransferBloc` never touches
  the aggregate or a repository directly, and never constructs
  `AccountService` itself — it's injected.
- `lib/presentation/transfer/transfer_ui_event.dart` — the sealed
  `TransferUiEvent` hierarchy: `TransferSubmitted` (maps to
  `TransferMoneyCommand`) and `AccountOverviewRequested` (maps to a query).
- `lib/presentation/transfer/transfer_ui_state.dart` — `TransferUiState`
  (`TransferStatus` + `AccountViewState?` + `error`), `Equatable` so
  `emit`'s de-dupe and `BlocBuilder`/`BlocSelector` rebuilds work correctly.
- `lib/presentation/transfer/transfer_bloc.dart` — `TransferBloc` itself:
  `on<TransferSubmitted>(_onTransferSubmitted, transformer: sequential())`
  and `on<AccountOverviewRequested>(_onAccountOverviewRequested, transformer: restartable())`.
  Each handler follows the same five-step seam: UI intent → build
  `TransferMoneyCommand` → `_accountService.transfer(command)` → re-read
  `AccountViewState` from the query side → `emit` a `TransferUiState`.
  `DomainError` (e.g. `InsufficientFundsError`) is caught and turned into a
  `failure` status with a message; it's never re-thrown into the UI as-is.
- `lib/presentation/transfer/transfer_di.dart` — `TransferPage` wires
  `AccountService` in with `RepositoryProvider.value` and `TransferBloc` in
  with `BlocProvider` (which auto-closes it), plus `TransferAuditObserver`,
  a `BlocObserver` you can install globally
  (`Bloc.observer = TransferAuditObserver()`) to log every `TransferUiEvent`
  as an audit trail — independent of, and never to be confused with, the
  ledger's own `LedgerEvent` log.

## What was verified

This sample was actually built as a runnable Flutter package (`pubspec.yaml`
depends on the real `fmodel`, `bloc`, `bloc_concurrency`, `flutter_bloc`, and
`equatable` packages from pub.dev) and checked with `flutter pub get` +
`flutter analyze`: **no issues found**. The domain/application stub files are
clearly marked as stand-ins for your existing code, not as part of the
`fmodel_bloc` skill's own output — the skill only ever produces the
`presentation/` layer and imports the rest.
