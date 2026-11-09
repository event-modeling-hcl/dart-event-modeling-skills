# Add-item Cubit wiring

Five files, meant to slot into your existing project (suggested paths are noted at the top of each file):

- `add_item_service.dart` — application-layer service, the "fmodel service" the Cubit talks to.
- `add_item_ui_state.dart` — the Cubit's state class.
- `add_item_cubit.dart` — the Cubit itself.
- `add_item_screen.dart` — the widget (form + list + spinner + error).
- `add_item_wiring.dart` — an example of composing everything, from your `addItemDecider`/`wardrobeView` down to a widget-ready `AddItemCubit`.

All five were checked with `flutter analyze` against a scratch project stubbing your domain types (`AddItemCommand`, `AddItemState`, `WardrobeEvent`, `ItemAddedEvent`, `WardrobeViewState`, `WardrobeItem`) and a real `fmodel` path dependency — zero issues.

## Naming: keeping domain and UI apart

Your domain already has an `AddItemState` — the Decider's write-model state in `lib/state_change/add_item/api.dart`. If the Cubit's state were also called `AddItemState`, every import list in the presentation layer would carry two types with the same name, and it'd be a matter of time before someone builds a list tile from the wrong one. So the Cubit's state is `AddItemUiState`, and it doesn't just borrow the name — it's structurally a different thing:

- `AddItemUiState` holds `List<WardrobeItem> items`, sourced from `WardrobeViewState` (the **read model**).
- The domain's `AddItemState` is the Decider's internal fold state, used only to decide whether a command is valid — the Cubit never sees it, references it, or redefines it.

`AddItemCommand`, `WardrobeEvent`, `ItemAddedEvent`, and `WardrobeViewState` are imported from your existing `api.dart` files everywhere they're needed; none of them are redefined in the presentation code.

## Why a Cubit, not a Bloc

This screen has exactly one user action — "tap Add" — mapped to exactly one outcome (loading → success/failure). A Bloc's event-to-state indirection buys you nothing here and adds a class you'd only ever construct one instance of. `AddItemCubit.addItem(name:, category:)` is called directly from the widget's `onPressed`.

## State shape

```dart
enum AddItemStatus { initial, loading, success, failure }

final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.items = const <WardrobeItem>[],
    this.errorMessage,
  });
  final AddItemStatus status;
  final List<WardrobeItem> items;
  final String? errorMessage;
  ...
}
```

`Equatable` gives it value equality so `BlocBuilder`/`BlocConsumer` only rebuild when something actually changed. `status` is a plain enum rather than a sealed-class hierarchy — four flat, mutually exclusive phases didn't seem to warrant the extra boilerplate of four subclasses, but if you'd rather pattern-match exhaustively with `switch`, it's a straightforward refactor to a sealed `AddItemUiState` with `AddItemInitial`/`AddItemLoading`/`AddItemSuccess`/`AddItemFailure` subtypes.

## Injecting the fmodel service

The Cubit never builds its own dependencies. `AddItemService` wraps the `EventSourcingAggregate<AddItemCommand, AddItemState, WardrobeEvent, NoMetadata, NoMetadata>` and `MaterializedView<WardrobeViewState, WardrobeEvent, NoMetadata>` you already build via `createEventSourcingAggregate(decider: addItemDecider, ...)` / `createMaterializedView(view: wardrobeView, ...)`, and exposes one method:

```dart
Future<WardrobeViewState> addItem(AddItemCommand command) async {
  WardrobeViewState? latestViewState;
  await for (final event in _aggregate.handle(command)) {
    latestViewState = await _materializedView.handle(event);
  }
  ...
  return latestViewState;
}
```

It runs the command through the aggregate, feeds every resulting event through the materialized view, and hands back the freshest read-model state — so the Cubit gets exactly what it needs to update `items` in one call, without knowing fmodel exists. `AddItemCubit`'s constructor takes an `AddItemService`:

```dart
AddItemCubit({required AddItemService addItemService})
```

`add_item_wiring.dart` shows the full chain, ending in `BlocProvider<AddItemCubit>(create: (_) => AddItemCubit(addItemService: addItemService), child: const AddItemScreen())`.

I assumed `CM`/`EM`/`M` (fmodel's metadata type parameters) are all `NoMetadata`, since nothing in your description mentions metadata. If your repositories actually use real metadata types, `AddItemService`'s two fields need those types substituted in instead.

## Domain rejection → failure state

`Decider.decide` returns a `Stream<E>`; when the domain rejects a command, the natural way to signal that is for `decide` to throw (or the stream to emit an error) before any event comes out. `AddItemService.addItem` doesn't catch that — it lets it propagate. `AddItemCubit.addItem` is the one place that catches it:

```dart
try {
  final updatedView = await _addItemService.addItem(command);
  emit(state.copyWith(status: AddItemStatus.success, items: updatedView.items, clearError: true));
} catch (error) {
  emit(state.copyWith(status: AddItemStatus.failure, errorMessage: _describeError(error)));
}
```

The catch is intentionally broad (`catch (error)`) because you didn't mention a specific exception type your decider throws. If you introduce one (say, `DuplicateItemException` or a `DomainError` base class), narrow the catch to it — you'll get compile-time safety on the mapping instead of stringly-typed messages, and can distinguish "domain rejected this" from "something actually broke" (e.g. re-throw unknown errors instead of showing them as a friendly message). The widget only ever sees the resulting `AddItemUiState.errorMessage`; nothing throws across the Cubit boundary.

## Widget

`AddItemScreen` reads two `TextEditingController`s, calls `context.read<AddItemCubit>().addItem(...)` on tap, and uses a single `BlocConsumer<AddItemCubit, AddItemUiState>`: the `builder` renders the form (disabled while loading), a `CircularProgressIndicator` swapped in for the button's label while `state.isLoading`, an inline error text when `state.hasError`, and the item list from `state.items`; the `listener` additionally pops a snackbar on new errors. It assumes `AddItemCubit` is provided above it in the tree — see `add_item_wiring.dart`.

## One assumption worth flagging

I assumed `WardrobeItem` exposes `name` and `category` fields (matching the two inputs the form collects) — adjust `add_item_screen.dart`'s `ListTile` if your actual shape differs. I also assumed `WardrobeEvent` is importable from the same `lib/state_change/add_item/api.dart` file that declares `addItemDecider`; if it actually lives in a separate shared events file in your project, just repoint that one import in `add_item_service.dart`, `add_item_cubit.dart`, and `add_item_wiring.dart` — nothing else changes.
