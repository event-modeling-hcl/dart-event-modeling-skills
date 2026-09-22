# Bloc Integration (event-driven)

The full **event-driven Bloc** path for wiring an fmodel-dart domain layer into a Flutter
screen: a `sealed <Screen>UiEvent` hierarchy, `on<E>` handlers, and `bloc_concurrency`
transformers for serialized or deduplicated command handling. This file assumes you have
already read [NAMING-AND-LAYERS.md](NAMING-AND-LAYERS.md); it does not repeat the naming
rules, only applies them. For the simpler method-driven path, see
[CUBIT-INTEGRATION.md](CUBIT-INTEGRATION.md).

## Table of contents

1. [When to choose Bloc over Cubit](#1-when-to-choose-bloc-over-cubit)
2. [The sealed `AddItemUiEvent` hierarchy](#2-the-sealed-additemuievent-hierarchy)
3. [The `AddItemUiState`](#3-the-additemuistate)
4. [The `AddItemBloc`](#4-the-additembloc)
5. [`bloc_concurrency` transformers](#5-bloc_concurrency-transformers)
6. [Transition vs. evolve](#6-transition-vs-evolve)
7. [When NOT to introduce a `UiEvent`](#7-when-not-to-introduce-a-uievent)
8. [Common mistakes recap](#8-common-mistakes-recap)

The running example throughout is the Wardrobe screen's "add item" feature, the same one
used in `SKILL.md` and `CUBIT-INTEGRATION.md`.

## 1. When to choose Bloc over Cubit

Both are first-class in this skill; Bloc is the *event-driven* variant and it earns its
extra ceremony (a `UiEvent` hierarchy, `on<E>` registration) only when one of these is true:

- You need a **`bloc_concurrency` transformer** — most commonly `sequential()`, to serialize
  command handling so two in-flight commands against the same event-sourced aggregate cannot
  race each other's `fetchEvents → decide → save` cycle.
- You want an **auditable stream of UI intents** — every `add(event)` is a discrete, typed,
  loggable fact about what the user asked for, which `BlocObserver.onEvent` can capture
  globally.
- You need **debounce/throttle/cancel-in-flight** semantics for a query, e.g. search-as-you-type
  cancelling a stale request via `restartable()`.

If none of these apply — the UI intent maps 1:1 onto a `Command` and there is no ordering or
cancellation concern — prefer a Cubit; a public method call *is* the command dispatch and
there is no `UiEvent` type to keep in sync. See
[CUBIT-INTEGRATION.md](CUBIT-INTEGRATION.md) for that path. Promote a Cubit to a Bloc later if
a concurrency need appears; the five-step seam (below) does not change, only its trigger does.

## 2. The sealed `AddItemUiEvent` hierarchy

A Bloc's "event" is **never** a domain event. It is a UI intent — a request the user (or the
system) is making of the screen. Name each case after the *intent*, in past/imperative-intent
form, never after a fact:

```dart
// presentation/add_item/add_item_ui_event.dart
part of 'add_item_bloc.dart';

/// UI intents for the Add Item screen. Each case maps to an fmodel `Command`
/// (or a query) inside `AddItemBloc` — none of these is a domain event.
sealed class AddItemUiEvent extends Equatable {
  const AddItemUiEvent();

  @override
  List<Object?> get props => [];
}

/// User tapped "Add". Maps to `AddItemCommand` in the `_onAddItemSubmitted`
/// handler — it does NOT map to `ItemAddedEvent`.
final class AddItemSubmitted extends AddItemUiEvent {
  const AddItemSubmitted({required this.name, required this.category});

  final String name;
  final String category;

  @override
  List<Object?> get props => [name, category];
}

/// Screen wants the current wardrobe projection (initial load or pull-to-refresh).
/// Maps to a query against the read side, not a command.
final class WardrobeRequested extends AddItemUiEvent {
  const WardrobeRequested();
}

/// User is typing in the wardrobe search box. Maps to a query per keystroke;
/// see `restartable()` in §5 for why this case needs it.
final class SearchQueryChanged extends AddItemUiEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}
```

**Look closely at the pair that trips people up:**

| Type                | Layer        | Meaning                                   |
| -------------------- | ------------ | ------------------------------------------ |
| `AddItemSubmitted`   | presentation | *intent* — "the user asked to add an item" |
| `ItemAddedEvent`     | domain       | *fact* — "an item was added"               |

`AddItemSubmitted` is a case of `AddItemUiEvent`, handled by `on<AddItemSubmitted>`, and it is
built and consumed entirely inside the Bloc. `ItemAddedEvent` is a case of the sealed
`WardrobeEvent`, produced by the `Decider`'s `decide` function and folded by `evolve` — the
Bloc never constructs one, never emits one, and never registers `on<ItemAddedEvent>` (it isn't
even the same type: `AddItemUiEvent` does not, and must not, extend or wrap `WardrobeEvent`).
The Bloc's only connection to `ItemAddedEvent` is indirect: after the aggregate persists it,
the read-side `View` folds it into `WardrobeViewState`, which the Bloc then reads back in
step 4 of the seam.

## 3. The `AddItemUiState`

Identical idiom to the Cubit path: one class, a status enum, `Equatable` for the de-dupe that
`emit` relies on, and render data pulled from the **read side** only.

```dart
// presentation/add_item/add_item_ui_state.dart
part of 'add_item_bloc.dart';

enum AddItemStatus { initial, loading, success, failure }

final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.wardrobe,
    this.error,
  });
  const AddItemUiState.initial() : this();

  final AddItemStatus status;
  final WardrobeViewState? wardrobe;   // read-model projection, never Decider state
  final String? error;

  AddItemUiState copyWith({
    AddItemStatus? status,
    WardrobeViewState? wardrobe,
    String? error,
  }) =>
      AddItemUiState(
        status: status ?? this.status,
        wardrobe: wardrobe ?? this.wardrobe,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, wardrobe, error];
}
```

`emit` compares the new `State` to the current one with `==` and silently drops a no-op emit,
which is why `AddItemUiState` extends `Equatable` — without it, two structurally identical
states would still compare unequal by identity and the Bloc would re-render needlessly.

## 4. The `AddItemBloc`

`Bloc<Event, State> extends BlocBase<State>`. There is no `mapEventToState` — that was removed
in bloc 8 — so every event type gets its own handler via `on<E>(handler, {transformer})`.
Calling `on<E>` twice for the same `E` throws `StateError` at registration time; calling
`add(event)` for a type with no registered handler throws too. The handler signature is
`FutureOr<void> Function(E event, Emitter<State> emit)` — use the `Emitter` passed in, never
call `bloc.emit` from outside a handler (it is `@visibleForTesting`).

The Bloc depends on a thin **application service**, injected through its constructor, never
constructed inside the Bloc. That service wraps the fmodel application layer so the Bloc never
touches a repository or a `Decider` directly:

```dart
// application/wardrobe_service.dart (owned by fmodel / upstream skill — shown for context only)
// aggregate: EventSourcingAggregate<AddItemCommand, AddItemState, WardrobeEvent, CM, EM>
//   built with createEventSourcingAggregate(decider: ..., eventRepository: ...)
//   aggregate.handle(C command) -> Stream<WardrobeEvent>   (event sourcing: fetch, decide, save)
// view:      MaterializedView<WardrobeViewState, WardrobeEvent, M>
//   built with createMaterializedView(view: ..., viewStateRepository: ...)
class WardrobeService {
  WardrobeService(this._aggregate, this._viewStateRepository);
  // ...
  Future<void> handle(AddItemCommand command) => _aggregate.handle(command).drain();
  Future<WardrobeViewState> wardrobe() => _viewStateRepository.fetchLatest();
  Future<WardrobeViewState> searchWardrobe(String query) =>
      _viewStateRepository.fetchMatching(query);
}
```

Now the Bloc itself, implementing the same five-step seam as the Cubit but triggered by
`on<E>` instead of a method call:

```dart
// presentation/add_item/add_item_bloc.dart
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

// Domain + application, owned by the fmodel layer — imported, never redefined.
import '../../state_change/add_item/api.dart';     // AddItemCommand, DomainError
import '../../state_view/wardrobe_view/api.dart';   // WardrobeViewState
import '../../application/wardrobe_service.dart';   // WardrobeService

part 'add_item_ui_event.dart';
part 'add_item_ui_state.dart';

class AddItemBloc extends Bloc<AddItemUiEvent, AddItemUiState> {
  AddItemBloc(this._service) : super(const AddItemUiState.initial()) {
    // Exactly one handler per concrete event type. `sequential()` serializes
    // command handling so two submits never race the same aggregate's
    // fetch -> decide -> save cycle. `restartable()` cancels a stale query
    // when a fresher one arrives, which is safe because queries are pure reads.
    on<AddItemSubmitted>(_onAddItemSubmitted, transformer: sequential());
    on<WardrobeRequested>(_onWardrobeRequested, transformer: restartable());
    on<SearchQueryChanged>(_onSearchQueryChanged, transformer: restartable());
  }

  final WardrobeService _service;

  Future<void> _onAddItemSubmitted(
    AddItemSubmitted event,
    Emitter<AddItemUiState> emit,
  ) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      // 1-2: UI intent -> fmodel Command. Never construct ItemAddedEvent here;
      // the aggregate's Decider decides which domain events (if any) result.
      final command = AddItemCommand(name: event.name, category: event.category);
      // 3: application layer runs decide -> evolve -> persist.
      await _service.handle(command);
      // 4: read fresh render data from the query side.
      final wardrobe = await _service.wardrobe();
      // 5: emit a UiState built from the read model, never the Decider state.
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: wardrobe));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  Future<void> _onWardrobeRequested(
    WardrobeRequested event,
    Emitter<AddItemUiState> emit,
  ) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      final wardrobe = await _service.wardrobe();
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: wardrobe));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<AddItemUiState> emit,
  ) async {
    // No loading flash on every keystroke; restartable() already guarantees
    // only the latest query's result reaches emit.
    final wardrobe = await _service.searchWardrobe(event.query);
    emit(state.copyWith(status: AddItemStatus.success, wardrobe: wardrobe));
  }
}
```

Nothing here is a domain type except what is imported: `AddItemCommand`, `WardrobeViewState`,
`DomainError`. `AddItemSubmitted`, `WardrobeRequested`, `SearchQueryChanged`, `AddItemUiEvent`,
`AddItemUiState`, `AddItemStatus`, `AddItemBloc` are all presentation types this skill owns.

## 5. `bloc_concurrency` transformers

Import `package:bloc_concurrency/bloc_concurrency.dart` and pass one as the `transformer:`
argument to `on<E>`. Each is an `EventTransformer<Event>` — a function from a `Stream<Event>`
and a mapper to an output `Stream`:

| Transformer      | Behavior                                                          | Use for                                                        |
| ---------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `sequential()`   | Processes events one at a time, strictly in arrival order; no handler overlap. | **Command-issuing handlers** — `AddItemSubmitted` — so concurrent submits can't race the same aggregate's fetch/decide/save cycle. |
| `droppable()`    | Runs the first event; ignores new ones until it finishes.          | A "submit" button that must not double-fire while already in flight (e.g. a bare-metal debounce with no cancel). |
| `restartable()`  | Cancels the in-flight handler when a new event arrives; only the latest survives. | **Query/search handlers** — `SearchQueryChanged`, or any reload where a stale in-flight response should be discarded, not queued. |
| `concurrent()`   | Runs every event's handler in parallel; results may arrive out of order. This is also `Bloc`'s **default** when no `transformer:` is given. | Independent operations with no ordering or shared-resource concern. Rarely what you want for a command handler. |

**Recommendation for this skill's shape:** `sequential()` for every handler that issues a
`Command` against an event-sourced aggregate (consistency depends on not racing the read →
decide → save cycle); `restartable()` for handlers that only read (`WardrobeRequested`,
`SearchQueryChanged`) since discarding a stale query result is always safe. Never leave a
command handler on the default `concurrent()` — that is exactly what reintroduces the race
`sequential()` exists to prevent.

## 6. Transition vs. evolve

Bloc has its own, unrelated notion of a "transition." `Bloc.onTransition` fires with a
`Transition<Event, State>` — the triple `(currentState, event, nextState)` — right before a
new `UiState` is emitted:

```dart
class AddItemBloc extends Bloc<AddItemUiEvent, AddItemUiState> {
  // ...
  @override
  void onTransition(Transition<AddItemUiEvent, AddItemUiState> transition) {
    super.onTransition(transition); // always call super first
    // A presentation-layer log/analytics hook only:
    log('AddItemUiEvent ${transition.event} -> ${transition.nextState.status}');
  }
}
```

This is **not** the same concept as fmodel's `evolve(S, E) -> S`. `evolve` is a pure fold of
one *domain* event into *domain* state, run inside the `Decider`/`View` to reconstruct the
write model or the read model from the event stream — it has no notion of a "current UI state"
or a "UI event" at all. `onTransition`'s `Transition` is a presentation-only bookkeeping record
of `(old UiState, UiEvent, new UiState)`, useful for logging or a `BlocObserver`, and it says
nothing about how domain events were folded to produce the `WardrobeViewState` embedded in that
`UiState`. Treat `onTransition` purely as an observability hook on the Bloc; the actual
event-sourced fold already happened, earlier, inside the application/domain layers, via
`evolve`.

## 7. When NOT to introduce a `UiEvent`

Reach for a Cubit instead — see [CUBIT-INTEGRATION.md](CUBIT-INTEGRATION.md) — when:

- Every intent maps 1:1 to a `Command` with no ordering, debouncing, or cancellation need. A
  method call already *is* the dispatch; a `sealed UiEvent` hierarchy would only add
  boilerplate (a class, an `Equatable` override, an `on<E>` registration) for no behavioral
  gain.
- You don't need an auditable event stream or a `BlocObserver` hook on this particular screen.
- The screen is simple enough that introducing `AddItemUiEvent` would only recreate the "Bloc
  Event ≠ Domain Event" collision risk (a new type to name and keep straight) without buying
  any of the concurrency control that justifies it.

If a screen starts simple as a Cubit and later needs `sequential()`/`restartable()`, promote it
to a Bloc then — the five-step seam and the `UiState` shape do not need to change, only the
trigger and the transformer.

## 8. Common mistakes recap

- Naming a `UiEvent` case after a domain fact (`ItemAdded` instead of `AddItemSubmitted`) — UI
  events name intents, not facts.
- Registering `on<AddItemUiEvent>` (the sealed base) instead of `on<AddItemSubmitted>` (the
  concrete case) — `on<E>` dispatches by concrete runtime type; a handler on the base type will
  not receive the events you expect, and each concrete case still needs its own handler.
- Calling `on<E>` twice for the same event type — throws `StateError` at registration.
- Leaving a command-issuing handler on the default `concurrent()` transformer — reintroduces
  the very race `sequential()` exists to prevent for event-sourced writes.
- Calling `bloc.emit(...)` directly from outside a handler instead of using the `Emitter`
  passed into `on<E>` — `emit` on the Bloc itself is `@visibleForTesting`.
- Building `AddItemUiState`'s `wardrobe` field from the Decider's `AddItemState` instead of the
  `View`'s `WardrobeViewState` — couples the UI to the write model and breaks CQRS.
- Confusing `onTransition`'s `Transition<Event, State>` with `evolve(S, E)` — one is a
  presentation-layer log hook, the other is the domain's event fold; see §6.
- Mapping a `UiEvent` directly to a domain `Event` (e.g. `emit`ting or constructing
  `ItemAddedEvent` inside the Bloc) — the Bloc issues a `Command`; only the `Decider` decides
  which domain events, if any, result.
