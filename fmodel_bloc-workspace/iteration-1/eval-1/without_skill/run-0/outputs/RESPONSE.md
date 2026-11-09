# Serializing fmodel-dart commands with a Bloc

Here's a `Bloc` (not `Cubit`) for the transfer screen, split into the pieces you asked for. All files are in this directory:

- `transfer_ui_event.dart` — the UI event(s)
- `transfer_ui_state.dart` — the state
- `transfer_bloc.dart` — the Bloc: handler registration + the `sequential()` transformer
- `transfer_money_service.dart` — turns the UI action into a `TransferMoneyCommand` and drives the aggregate
- `transfer_feature.dart` — DI/composition wiring (builds the Bloc, installs an audit observer)
- `transfer_money_domain.dart` — a minimal stand-in for your existing `Decider`/`AccountState`/`LedgerEvent`/aggregate, included only so this example compiles and `dart analyze` passes on its own; you already have the real version of this.

I also added a `pubspec.yaml` and validated the whole thing with `dart pub get` + `dart analyze` (zero issues) against your real local `fmodel-dart` checkout and the `bloc`/`bloc_concurrency` packages, and smoke-ran two rapid `TransferSubmitted` events through the Bloc to confirm they're handled strictly one after another (`submitting → failure → submitting → failure`, never interleaved).

## The naming fix

You said "event" is overloaded and you keep mixing up ledger events with bloc events — that's the most important thing to get right here, because `Bloc<Event, State>` bakes the word "Event" into the type signature itself, so it's very easy to end up with a `TransferEvent` that shadows or gets confused with `LedgerEvent`.

The convention used throughout:

| Concept | Type | Where it comes from |
|---|---|---|
| "the user did X" | `TransferUiEvent` (sealed), cases like `TransferSubmitted` | Input to the Bloc, added via `bloc.add(...)` |
| "the write model decided Y happened" | `LedgerEvent` (sealed), cases like `MoneyTransferred` | Output of `Decider.decide`, consumed via `aggregate.handle(command)` |
| "what the screen should show" | `TransferUiState` | Output of the Bloc |

Every Bloc-facing type gets an explicit `Ui` marker — `TransferUiEvent`, `TransferUiState` — precisely so it never reads like a domain type. `LedgerEvent` never gets anywhere near the Bloc's public API: the Bloc imports `transfer_money_service.dart`, not `transfer_money_domain.dart` directly, and the handler never references `LedgerEvent` by name.

## Why `sequential()`, specifically

`EventSourcingAggregate.handle(command)` does three things every time it's called: fetch the current event stream, fold it into state and call `decide` on it, then save whatever new events `decide` produced. That's a classic read-modify-write cycle over the *same* account's event stream.

If two `TransferSubmitted` events for the same account are in flight at once, two separate `handle()` calls can both fetch the same "current" stream, both decide against it independently, and both append — neither one sees the other's effect. That's exactly the race you said you can't allow. bloc's four transformers respond to that risk very differently:

- **`concurrent()`** (the Bloc default) — runs handlers in parallel. This is the race you're trying to prevent.
- **`droppable()`** — ignores new events while one is in flight. Silently discards a legitimate second transfer the user asked for; wrong for money movement.
- **`restartable()`** — cancels the in-flight handler when a new event arrives. Worse than `droppable()` here: it can abort a `handle()` call that already reached the `save()` step, leaving you unsure whether the transfer actually persisted.
- **`sequential()`** — queues events and processes them one at a time, **in the order `add()` was called**, with no overlap. Each `TransferSubmitted` handler runs to completion (including `save`) before the next one starts, so every submission sees the effects of the one before it. This is the one that actually gives you "strictly one at a time, in order."

It's applied only to the handler that needs it:

```dart
on<TransferSubmitted>(_onTransferSubmitted, transformer: sequential());
on<TransferResultAcknowledged>(_onTransferResultAcknowledged); // default transformer — fine, no shared resource
```

`sequential()` is per-`on<E>()` registration, not global to the Bloc — there's no reason to pay a queuing cost for a UI event (like dismissing a banner) that never touches the aggregate.

One caveat worth flagging: `sequential()` serializes *this Bloc instance's* handler calls. If the same account can also be reached from another screen, another Bloc instance, a background job, etc., you need concurrency control at the aggregate/event-store level too (e.g. `EventSourcingLockingAggregate` with optimistic locking, which fmodel-dart also has) — `sequential()` alone only protects against races *within this Bloc*.

## How the handler turns the UI action into the fmodel command

`transfer_bloc.dart`'s `_onTransferSubmitted` does exactly three things, and nothing else:

1. Emit an intermediate `submitting` state.
2. Await `_transferMoneyService.transfer(...)`, which is where the `TransferMoneyCommand` actually gets constructed and handed to `TransferMoneyAggregate.handle`.
3. Emit `success` (with a read-side `TransferHistoryEntry` folded into `state.history`) or catch `TransferRejectedException` and emit `failure`.

The command construction and the `LedgerEvent` handling both live in `transfer_money_service.dart`, not in the Bloc. `TransferMoneyService.transfer()`:

- builds the `TransferMoneyCommand` (with a fresh idempotency-key-style request id),
- calls `_transferMoneyAggregate.handle(command)`, collecting the resulting `Stream<LedgerEvent>`,
- inspects those `LedgerEvent`s to decide success vs. rejection,
- and maps the successful case into a `TransferHistoryEntry` — a small UI-facing DTO, not the write-model `AccountState` and not a `LedgerEvent`.

That mapping step is the CQRS seam: the Bloc's state (`TransferUiState.history`) is built from read-side-shaped data returned by the service, never from `AccountState` directly. `AccountState` stays entirely inside the write model.

## DI

`TransferMoneyService` is injected into `TransferBloc` via the constructor — the Bloc never builds it, and never touches the decider or event repository directly:

```dart
class TransferBloc extends Bloc<TransferUiEvent, TransferUiState> {
  TransferBloc({required TransferMoneyService transferMoneyService})
      : _transferMoneyService = transferMoneyService,
        super(const TransferUiState()) {
    on<TransferSubmitted>(_onTransferSubmitted, transformer: sequential());
    on<TransferResultAcknowledged>(_onTransferResultAcknowledged);
  }
  ...
}
```

`transfer_feature.dart` is the composition root: it builds the decider, the event repository, the aggregate, the service, and finally the Bloc (`buildTransferBloc()`). Wire that into `BlocProvider` the normal way:

```dart
BlocProvider(
  create: (_) => buildTransferBloc(eventRepository: myRealEventRepository),
  child: const TransferScreen(),
)
```

and dispatch from the UI with nothing more than:

```dart
context.read<TransferBloc>().add(
  TransferSubmitted(
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    amountMinorUnits: amountMinorUnits,
    currency: currency,
  ),
);
```

Rapid double-taps just enqueue two `TransferSubmitted` UI events back to back; `sequential()` is what makes sure they don't race.

## The auditable stream of what the user did

Because everything the user does arrives as a `TransferUiEvent` through `bloc.add()`, you get an ordered, replayable record of intent for free — that's the concrete benefit of choosing `Bloc` over `Cubit` here, beyond the concurrency control. Two ways to tap into it, both shown in the code:

- **`Bloc.onEvent`** (overridden in `transfer_bloc.dart`) — fires for every `TransferUiEvent` this Bloc receives, in arrival order, before its handler runs.
- **`BlocObserver`** (`AuditingBlocObserver` in `transfer_feature.dart`) — the app-wide version of the same hook; install it once via `Bloc.observer = const AuditingBlocObserver()` in `main()` and it sees `onEvent`/`onTransition`/`onError` for every Bloc in the app, not just this one.

Either hook only ever sees `TransferUiEvent`s (what the user asked for) — never `LedgerEvent`s (what actually got recorded), which is exactly the separation you asked for.
