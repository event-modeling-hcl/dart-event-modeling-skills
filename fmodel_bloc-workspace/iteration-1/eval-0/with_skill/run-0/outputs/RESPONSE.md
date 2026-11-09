## What I built

Four files, following the `fmodel_bloc` skill's Cubit path (your screen is a textbook
1:1 "tap Add -> run one command" case, so a Cubit is the right choice over a Bloc — no
ordering/debounce need, and a Cubit has no `UiEvent` type at all):

- **`add_item_cubit.dart`** + **`add_item_ui_state.dart`** (a `part`/`part of` pair, per
  bloc convention) — the presentation layer. `AddItemCubit` has two public methods:
  `loadWardrobe()` (populate the screen on open, no command involved) and `addItem({name,
  category})` (the five-step seam: build `AddItemCommand` -> call the service -> re-read
  the projection -> emit a new `AddItemUiState`).
- **`wardrobe_service.dart`** — the application-layer façade and the fmodel injection
  point. `WardrobeService` wraps your `EventSourcingAggregate<AddItemCommand, AddItemState,
  WardrobeEvent, NoMetadata, NoMetadata>` (built from `addItemDecider` via fmodel's
  `createEventSourcingAggregate`) for writes, and a `WardrobeReader` — a small
  `Future<WardrobeViewState> Function()` typedef — for reads. `buildWardrobeService(...)`
  is the composition-root helper you call once (e.g. in `main.dart`) to wire it all up.
- **`add_item_page.dart`** — the widget layer: `AddItemPage` does the DI
  (`RepositoryProvider<WardrobeService>` -> `BlocProvider<AddItemCubit>`), and
  `_AddItemView`/`_AddItemForm` render the name/category fields, the Add button (inline
  spinner while submitting, disabled during submission), the item list, and a
  `SnackBar` + inline error text when the domain rejects the command.

## Why the naming avoids collision

Every presentation type carries a `Ui` marker, and every domain type keeps exactly the
name your existing code already gave it — imported, never redefined:

| Name | Layer | What it is |
| --- | --- | --- |
| `AddItemCommand` | domain (yours) | intent -> `decide` input |
| `AddItemState` | domain (yours) | Decider's write-model, folded internally |
| `WardrobeViewState` | domain (yours) | read-model projection |
| `AddItemUiState` | presentation (new) | what the screen renders: `status` + `wardrobe` + `error` |
| `AddItemStatus` | presentation (new) | `initial \| loading \| success \| failure` |
| `AddItemCubit` | presentation (new) | the state holder |

The one collision this setup makes structurally impossible: `AddItemUiState.wardrobe` is
always populated by `WardrobeService.wardrobe()` — a **read-side** query — and never by
folding the Decider's `AddItemState`. So "Bloc State" and "Aggregate/Decider State" are
provably different objects in this code, not just different names. And because this is a
Cubit, there's no `AddItemUiEvent` sitting next to your `ItemAddedEvent` inviting someone
to confuse a UI intent with a domain fact — the Cubit's methods (`addItem`, `loadWardrobe`)
are the only "events" this screen has, and they're not domain events at all.

## Two things to double-check against your actual code

1. **`DomainError`** — I imported it from `state_change/add_item/api.dart` alongside
   `AddItemCommand`, assuming your consolidated `api.dart` also exports the sealed error
   type `addItemDecider` throws on rejection. If `DomainError` actually lives in a
   separate shared file (e.g. `lib/domain/errors.dart`), it's a one-line import change in
   `add_item_cubit.dart` — nothing else moves.
2. **`WardrobeReader`** — you told me the read side has a `View` and an already-built
   `MaterializedView`, but not the concrete repository/query behind it. Rather than invent
   a repository class name you might not have, `wardrobe_service.dart` takes reads as a
   plain `Future<WardrobeViewState> Function()` you supply at composition time — wrap
   whatever your `MaterializedView`'s backing `ViewStateRepository` already exposes (a
   query, a map lookup, a Drift/Hive read) in a function of that shape and pass it to
   `buildWardrobeService(wardrobeReader: ...)`. Nothing in the Cubit or the widget needs
   to change no matter what that storage turns out to be.

All four `.dart` files pass `dart format` (parse-clean); I couldn't run `dart analyze`
against them in isolation since they reference your existing domain/application code,
which isn't in this workspace.
