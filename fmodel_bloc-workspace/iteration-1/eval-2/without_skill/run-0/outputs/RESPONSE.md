# Untangling `AddItemEvent` / `ItemAddedEvent` / `AddItemState` × 2

## The four things you actually have

You have two independent layers, each with its own event/command/state
vocabulary, and the names currently collide because both layers borrowed the
same feature name ("Add Item") instead of naming things after their *role*.

| # | Current name | Lives in | What it actually is |
|---|---|---|---|
| 1 | `AddItemEvent` | bloc | **UI intent.** A record of something the user did ("submitted the add-item form"). Input to the Bloc. Nothing has happened in the domain yet. |
| 2 | `ItemAddedEvent` | decider | **Domain event.** A fact: the write model decided an item *was* added. Output of `decide`, input to `evolve`. Immutable history. |
| 3 | `AddItemState` (bloc) | bloc | **View/UI state.** What the widget tree renders right now (idle / loading / success / error). Output of the Bloc. |
| 4 | `AddItemState` (decider) | decider | **Write-model fold state.** The `S` in `Decider<C, S, E>` — the aggregate's current data, reconstructed by folding events through `evolve`, used only so `decide` can make its next decision. |

The mental model, fmodel's own vocabulary:

```
UI layer:      UI event  --[Bloc]-->  UI state
                  |                      ^
                  v                      |
Domain layer:  Command  --[decide]--> Event --[evolve]--> (write) State
```

Four distinct concepts, two per layer, and they must **never** share a name,
because a shared name is what let the bug below get written without anyone
noticing at the call site.

## What to rename, what to leave alone

**Leave alone:**
- `ItemAddedEvent` — correctly named. It's a fact, past tense, scoped to the
  aggregate (`Item`), not to a UI screen. This is the fmodel convention and
  it's already right.

**Rename:**

1. `AddItemEvent` (bloc) → **`AddItemRequested`**
   Bloc events should read as things that *already happened in the UI*, not
   as a generic "Event" — that's why `flutter_bloc`'s own docs favor names
   like `CounterIncrementPressed` over `IncrementEvent`. Doing this also
   removes the word "Event" from the UI vocabulary entirely, so it can never
   again be typo-confused with a domain event in a diff or a stack trace.

2. `AddItemState` (decider, the `S` type) → **`ItemState`**
   This is the deeper issue, not just a collision fix: a decider's fold
   state is evolved by *every* command the aggregate accepts — `AddItem`
   today, probably `RemoveItem` or `RenameItem` tomorrow. Naming it after
   one command (`AddItemState`) is itself a modeling smell; it should be
   named after the aggregate root it represents. Once it's `ItemState`, it
   can't collide with anything UI-side, on this feature or the next one.

3. `AddItemState` (bloc) → **`AddItemViewState`**
   Marking it explicitly as a *view* projection makes it obvious in an
   import list, a stack trace, or a code review comment which "state" is
   being discussed. (`AddItemUiState` works equally well — pick one suffix
   and use it project-wide.)

Net result: `AddItemRequested` → `AddItemCommand` → `ItemAddedEvent` →
`ItemState` (write model) → `AddItemViewState` (UI). Five names, zero
collisions, and every name tells you which layer it belongs to just by
reading it.

## The bug

> "My bloc's `AddItemEvent` handler currently constructs the domain
> `ItemAddedEvent` directly and I think that's wrong." — it is.

The old handler was doing roughly this:

```dart
on<AddItemEvent>((event, emit) {
  emit(AddItemState.loading());
  final domainEvent = ItemAddedEvent(itemId: event.itemId, name: event.name);
  // ...persist domainEvent somewhere, or just trust it happened...
  emit(AddItemState.success());
});
```

This is wrong for a specific, structural reason, not just a style one:
**`ItemAddedEvent` is the *output* of `itemDecider.decide`.** It is only
supposed to exist after the decider has looked at the current `ItemState`
and decided the command is valid. By constructing it in the Bloc instead:

- Every business rule the decider encodes (e.g. "you can't add an item that
  already exists," reflected here as `ItemAdditionRejectedEvent`) is
  silently skipped. The UI *always* reports success, whether or not the
  write model would actually have accepted the command.
- The event never goes through `EventSourcingAggregate.handle()`, so it's
  never appended via the `EventRepository`. The UI can show "success" while
  nothing was actually persisted to the event store — the UI's belief about
  the world and the write model's recorded history diverge.
- The Bloc now has to know the exact shape of a domain event (field names,
  defaulting rules, ID generation) — the opposite of the decoupling
  event-sourcing is meant to buy you. Any change to `ItemAddedEvent`'s
  constructor now has to be made in two unrelated places.

**The fix:** the Bloc's only job on the way *in* is translating UI intent
into a domain **command**, then calling `handle()` and reacting to whatever
events come back. It must never instantiate a domain event itself.

```dart
final command = domain.AddItemCommand(itemId: requested.itemId, name: requested.name);
final resultingEvents = await _itemAggregate.handle(command).toList();
emit(_viewStateFor(resultingEvents)); // maps ItemAddedEvent -> AddItemSuccess, etc.
```

See `add_item_bloc.dart` for the full corrected handler.

## The reusable rule

Apply this on every feature, not just this one:

1. **Name by role, not by feature.**
   - Domain command: `<Verb><Aggregate>Command` (`AddItemCommand`,
     `RemoveItemCommand`) — intent, input to `decide`.
   - Domain event: `<Aggregate><PastTenseVerb>Event` (`ItemAddedEvent`) —
     fact, output of `decide` / input to `evolve`.
   - Domain state: `<Aggregate>State` (`ItemState`) — named after the
     aggregate root, *never* after a single command, since one state is
     shared by every command/event the decider handles.
   - Bloc event: `<Aggregate><PastTenseVerb>` with no "Event" suffix at all
     (`AddItemRequested`) — a record of UI interaction, not a domain fact.
   - Bloc state: `<Feature>ViewState` or `<Feature>UiState` — a rendering
     projection, explicitly marked as view-layer.

2. **Alias every cross-layer import.** Import the domain module with a
   prefix everywhere it's used from the UI layer:
   ```dart
   import 'item_decider.dart' as domain;
   ```
   and only ever reference domain types as `domain.AddItemCommand`,
   `domain.ItemAddedEvent`, `domain.ItemState`. This isn't just cosmetic —
   it makes the boundary visible at every call site. In code review, a line
   like `domain.ItemAddedEvent(...)` appearing inside a Bloc's event handler
   (instead of inside `decide`) becomes instantly suspicious, because the
   prefix advertises "this is a domain type" right where the misuse would
   happen. Without the prefix, that same misuse reads as an unremarkable
   local constructor call and slips through review, which is exactly what
   happened here.

3. **One-directional dependency: UI → Domain, never the reverse.** The Bloc
   may import the domain module to build commands and read event data. The
   decider file must never import anything from the presentation layer. If
   you want this enforced mechanically, an import-linter rule or a folder
   boundary (`lib/domain` cannot import `lib/presentation`) makes it a build
   failure instead of a review nitpick.

4. **Only `decide` constructs events.** As a grep-able invariant: outside of
   a decider's `decide` function (and tests that exercise it directly), no
   file should contain a bare `EventTypeName(` constructor call for any type
   in your domain event hierarchy. If you see one in a Bloc, a widget, or a
   repository, that's the same bug in a new location.

Following this rule, a fifth feature ("remove item," "rename item," ...)
will never again produce a same-named UI/domain pair, because the two
vocabularies literally cannot overlap: one always ends in a role suffix that
belongs only to the UI layer, and the other is always spelled with a
`domain.` prefix at every point the UI layer touches it.

## Files in this directory

- `add_item_event.dart` — the bloc event, renamed `AddItemEvent` → `AddItemRequested`.
- `add_item_view_state.dart` — the bloc state, renamed `AddItemState` → `AddItemViewState`.
- `add_item_bloc.dart` — the corrected `AddItemBloc`: UI intent → `domain.AddItemCommand` → `_itemAggregate.handle()` → `domain.ItemEvent`s → `AddItemViewState`. No domain event is ever constructed here.
- `item_decider.dart` — supporting context (not one of the three requested files): the domain layer, showing `AddItemCommand`, `ItemAddedEvent` (unchanged) and the decider state renamed `AddItemState` → `ItemState`, wired with `fmodel`'s `Decider` and `EventSourcingAggregate`.
