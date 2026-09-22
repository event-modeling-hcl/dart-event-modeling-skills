# Cubit Integration

The full method-driven path for wiring an fmodel-dart domain/application layer into a
`Cubit`. Read [NAMING-AND-LAYERS.md](NAMING-AND-LAYERS.md) first if any name here looks
unfamiliar — this file assumes that vocabulary and does not redefine it.

## Table of contents

1. When to use a Cubit
2. Anatomy of the UiState
3. The Cubit
4. The application service façade
5. Read-model consistency after a command
6. Before / after: the muddy version vs the clean version
7. Common mistakes

## 1. When to use a Cubit

Use a `Cubit` when a screen's UI intents map 1:1 onto fmodel `Command`s and nothing needs
ordering, debouncing, or a `bloc_concurrency` transformer. A public method call *is* the
command dispatch — there is no `<Screen>UiEvent` type to define, so the "Bloc Event ≠ Domain
Event" collision described in the parent skill cannot even arise here. This is the default
choice; only reach for a Bloc (see `BLOC-INTEGRATION.md`) once a real ordering/concurrency
requirement shows up. The Wardrobe "add item" screen used throughout this file is a textbook
Cubit case: tap a button, run one command, refresh one projection.

## 2. Anatomy of the UiState

A `Cubit<State>`'s `emit` de-dupes consecutive equal states (`==`), so `UiState` **must** use
value equality — `package:equatable`, with every field listed in `props`. Skipping this either
breaks de-duping silently or, worse, makes two visually different states compare equal because
a field was left out of `props`.

Prefer a single class carrying a status enum over a sealed hierarchy of one-class-per-status.
It keeps partial data (e.g. the last successful `wardrobe` projection while a new `loading`
is in flight) trivial to retain instead of discarding it every transition.

```dart
// presentation/add_item/add_item_ui_state.dart
part of 'add_item_cubit.dart';

/// Lifecycle of the screen. `initial` is pre-fetch; `loading` covers both the
/// first fetch and every subsequent command; `success`/`failure` describe the
/// outcome of the most recent command or fetch.
enum AddItemStatus { initial, loading, success, failure }

/// What the Add Item screen renders. Note what is absent: no `AddItemState`
/// (the Decider's write-model) anywhere in here. `wardrobe` is the read-model
/// projection — the only render data the clean CQRS rule allows.
final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.wardrobe,
    this.error,
  });

  const AddItemUiState.initial() : this();

  final AddItemStatus status;
  final WardrobeViewState? wardrobe; // read-model projection, never Decider state
  final String? error;

  bool get isSubmitting => status == AddItemStatus.loading;

  AddItemUiState copyWith({
    AddItemStatus? status,
    WardrobeViewState? wardrobe,
    String? error,
  }) =>
      AddItemUiState(
        status: status ?? this.status,
        // Keep the last known-good projection on failure instead of losing it —
        // see "Common mistakes" (#7) for why nulling it out here is a bug.
        wardrobe: wardrobe ?? this.wardrobe,
        error: error,
      );

  @override
  List<Object?> get props => [status, wardrobe, error];
}
```

`error` is left un-defaulted in `copyWith` (rather than `error ?? this.error`) so a successful
transition can explicitly clear a previous failure by passing `error: null`.

## 3. The Cubit

Constructor-inject a single application service — never construct an aggregate, a view, or a
repository inside the Cubit. Every method follows the same shape: flip to `loading`, run the
five-step seam, land on `success` or `failure`.

```dart
// presentation/add_item/add_item_cubit.dart
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Domain + application, owned by the fmodel layer — imported, never redefined.
import '../../state_change/add_item/api.dart';    // AddItemCommand
import '../../state_change/remove_item/api.dart'; // RemoveItemCommand
import '../../state_view/wardrobe_view/api.dart'; // WardrobeViewState
import '../../domain/errors.dart';                // DomainError
import '../../application/wardrobe_service.dart'; // WardrobeService

part 'add_item_ui_state.dart';

class AddItemCubit extends Cubit<AddItemUiState> {
  AddItemCubit(this._service) : super(const AddItemUiState.initial());

  final WardrobeService _service;

  /// Initial fetch — no command, just the query side. Call this once, e.g.
  /// from the widget that creates the Cubit, to populate the screen before
  /// the user does anything.
  Future<void> loadWardrobe() async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      final view = await _service.wardrobe(); // step 4 only, no step 2/3
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: view, error: null));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  /// One UI intent, one command. This is the five-step seam in full.
  Future<void> addItem({required String name, required String category}) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      // 1–2: intent -> Command.
      final command = AddItemCommand(name: name, category: category);
      // 3: application layer runs decide -> emits domain events -> persists.
      await _service.handle(command);
      // 4: read fresh render data from the query side.
      final view = await _service.wardrobe();
      // 5: emit a UiState carrying that projection + status.
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: view, error: null));
    } on DomainError catch (e) {
      // Map the domain error to a status; never let it propagate to the widget.
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  /// A second command on the same screen and the same UiState. Nothing about
  /// the seam changes — only the command type and which aggregate handles it.
  Future<void> removeItem(String itemId) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      await _service.handle(RemoveItemCommand(itemId: itemId));
      final view = await _service.wardrobe();
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: view, error: null));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }
}
```

Catch `DomainError` specifically, not `Object`/`Exception`. A broad catch swallows genuine
bugs (a null-check failure, a repository timeout) and reports them to the user as if they were
a rejected command — see "Common mistakes" (#5).

## 4. The application service façade

The Cubit must depend on exactly one collaborator. When a screen needs more than one command
(here: add and remove), the façade — not the Cubit — is what fans out to the aggregates each
command needs, and folds the query side into a single `wardrobe()` read.

```dart
// application/wardrobe_service.dart
import 'package:fmodel/fmodel.dart';

import '../state_change/add_item/api.dart';    // AddItemCommand, AddItemState
import '../state_change/remove_item/api.dart'; // RemoveItemCommand, RemoveItemState
import '../state_view/wardrobe_view/api.dart'; // WardrobeViewState, WardrobeQuery
import 'wardrobe_event.dart';                  // WardrobeEvent

/// The Cubit's ONE collaborator. Wraps the write-side aggregate(s) this
/// screen needs plus the read-side view, so presentation code never sees an
/// fmodel repository or Decider directly.
class WardrobeService {
  WardrobeService({
    required this.wardrobeId,
    required EventSourcingAggregate<AddItemCommand, AddItemState, WardrobeEvent> addItemAggregate,
    required EventSourcingAggregate<RemoveItemCommand, RemoveItemState, WardrobeEvent> removeItemAggregate,
    required EphemeralView<WardrobeViewState, WardrobeQuery> wardrobeView,
  })  : _addItemAggregate = addItemAggregate,
        _removeItemAggregate = removeItemAggregate,
        _wardrobeView = wardrobeView;

  final String wardrobeId;
  final EventSourcingAggregate<AddItemCommand, AddItemState, WardrobeEvent> _addItemAggregate;
  final EventSourcingAggregate<RemoveItemCommand, RemoveItemState, WardrobeEvent> _removeItemAggregate;
  final EphemeralView<WardrobeViewState, WardrobeQuery> _wardrobeView;

  /// Step 3 of the seam, for any command this screen supports. Dispatches by
  /// runtime type to the aggregate that owns it — the Cubit still calls one
  /// method regardless of how many aggregates back this façade.
  Future<void> handle(Object command) => switch (command) {
        AddItemCommand c => _addItemAggregate.handle(c).drain<void>(),
        RemoveItemCommand c => _removeItemAggregate.handle(c).drain<void>(),
        _ => throw ArgumentError('WardrobeService cannot handle $command'),
      };

  /// Step 4 of the seam. `EventSourcingAggregate.handle` returns a
  /// `Stream<E>`; `.drain<void>()` consumes it so persistence completes
  /// before `handle` resolves.
  Future<WardrobeViewState> wardrobe() => _wardrobeView.handle(WardrobeQuery(wardrobeId));
}
```

The repositories behind `_addItemAggregate`, `_removeItemAggregate`, and `_wardrobeView` are
fmodel **ports** (`EventRepository`, `EphemeralViewRepository`, ...); their adapters live in
the domain/application slices produced by the upstream `map-event-model-hcl-to-code` skill.
This file only composes them — it never implements a port. Composition happens once, near
`RepositoryProvider`:

```dart
final wardrobeService = WardrobeService(
  wardrobeId: wardrobeId,
  addItemAggregate: createEventSourcingAggregate(
    decider: addItemDecider,              // Decider<AddItemCommand, AddItemState, WardrobeEvent>
    eventRepository: wardrobeEventRepository,
  ),
  removeItemAggregate: createEventSourcingAggregate(
    decider: removeItemDecider,           // Decider<RemoveItemCommand, RemoveItemState, WardrobeEvent>
    eventRepository: wardrobeEventRepository,
  ),
  wardrobeView: createEphemeralView(
    view: wardrobeView,                   // View<WardrobeViewState, WardrobeEvent>
    ephemeralViewRepository: wardrobeQueryRepository,
  ),
);
```

## 5. Read-model consistency after a command

Step 4 needs fresh render data right after step 3 persists new events. fmodel-dart offers two
ways to get it; either is valid, pick per screen:

- **Ephemeral view (fold-on-read).** `createEphemeralView(view:, ephemeralViewRepository:)`
  gives you `Future<S> handle(Q query)`: it re-reads the relevant events and folds them with
  `View.evolve` on every call. This is what `WardrobeService.wardrobe()` above does. No moving
  parts beyond the event store, so there is no lag between "command persisted" and "query sees
  it" — correct by construction, at the cost of re-folding on every read.
- **Materialized view (projector-updated).** `createMaterializedView(view:, viewStateRepository:)`
  gives you `Future<S> handle(E event)`, called by a separate subscription/projector process
  as new events arrive, which persists the folded `S` into a `ViewStateRepository`. The façade
  then just reads the stored projection:

  ```dart
  Future<WardrobeViewState> wardrobe() => _viewStateRepository.fetch(wardrobeId);
  ```

  Cheaper to read, but the projector may lag behind the aggregate by a beat — acceptable for
  most UIs, but know that `wardrobe()` immediately after `handle(command)` can theoretically
  observe stale data if the projector has not caught up yet.

Either way, the Cubit's code does not change — it always calls `_service.wardrobe()` and never
knows which strategy backs it. That indirection is the payoff of the service façade.

## 6. Before / after: the muddy version vs the clean version

**Muddy** — a bare, colliding state name, and the UiState renders the write-model directly:

```dart
// DO NOT DO THIS.
class AddItemState extends Equatable {        // collides with the domain's AddItemState
  const AddItemState(this.decider, this.isLoading);
  final AddItemState decider;                 // wait — which AddItemState is this?
  final bool isLoading;
  @override
  List<Object?> get props => [decider, isLoading];
}

class AddItemCubit extends Cubit<AddItemState> {
  AddItemCubit(this._aggregate) : super(const AddItemState(AddItemState.initial(), false));
  final EventSourcingAggregate<AddItemCommand, AddItemState, WardrobeEvent> _aggregate;

  Future<void> addItem(String name, String category) async {
    final events = await _aggregate.handle(AddItemCommand(name: name, category: category)).toList();
    final next = events.fold(state.decider, (s, e) => /* re-implements evolve here */ s);
    emit(AddItemState(next, false));           // write-model leaks straight into the UI
  }
}
```

This compiles, but the type name is ambiguous at every call site, the Cubit reimplements
`evolve` instead of reading a projection, and it depends on a raw aggregate instead of an
injected service — three violations at once.

**Clean** — the version from sections 2–4 of this file: `AddItemUiState` (never a bare
`AddItemState`), built from `WardrobeViewState` (the read side), via an injected
`WardrobeService` (one collaborator, not a raw aggregate).

## 7. Common mistakes

- Naming the Cubit's state `AddItemState` instead of `AddItemUiState` — collides with the
  domain's write-model type name and is the exact ambiguity this skill removes.
- Building `UiState` render data from the Decider/aggregate state instead of the View
  projection — couples the UI to the write side and breaks `Bloc State ≠ Aggregate State`.
- Forgetting `Equatable`/`props`, or leaving a field out of `props` — `emit` either never
  de-dupes or de-dupes states that are not actually equal.
- Nulling out `wardrobe` in `copyWith` on every transition instead of defaulting to
  `wardrobe ?? this.wardrobe` — a failed command then blanks a screen that had good data.
- Catching `Object`/`Exception` instead of `DomainError` — hides real bugs behind a generic
  "failure" status meant for rejected commands.
- Constructing the aggregate, view, or `WardrobeService` inside the Cubit — makes it
  untestable without a real event store. Inject it through the constructor.
- Giving a Cubit a `UiEvent` type "for consistency with Bloc" — a Cubit has none by design;
  its methods are the intent. If you find yourself wanting one, you likely need a Bloc instead
  (see `BLOC-INTEGRATION.md`).
