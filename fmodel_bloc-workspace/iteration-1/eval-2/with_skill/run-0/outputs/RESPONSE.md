# Untangling `AddItemEvent` / `ItemAddedEvent` / `AddItemState`

You have a real collision, and it's the exact collision fmodel + bloc produces whenever the
presentation layer doesn't mark itself distinctly from the domain layer. Below: what each of
your four types actually *is*, exactly what to rename, the bug in your handler, and a rule you
can apply to every screen from now on.

## 1. What each thing actually is

Both fmodel and bloc use the words "event" and "state" — for different concepts. That's the
whole problem.

| Your type | Layer | What it really is |
| --- | --- | --- |
| `class AddItemEvent` (bloc file) | **presentation** | A **UI intent** — "the user tapped Add". It is a request, not a fact. It may be rejected (validation, a domain error). |
| `ItemAddedEvent` (decider) | **domain** | A **domain event** — a fact that already happened, emitted by `decide()` as output, folded by `evolve()` as input. Immutable, past tense, cannot be rejected because it already occurred. |
| `AddItemState` (bloc file) | **presentation** | The **UI state** — what the widget renders: some read-model data plus a status (`loading`/`success`/`failure`). |
| `AddItemState` (decider) | **domain** | The **write-model / Decider state** — the aggregate's internal state, reconstructed by folding domain events with `evolve(state, event)`. It exists to make the next `decide()` call possible; the UI should never see it directly. |

The three equalities that must never blur, stated precisely:

- **Bloc Event ≠ Domain Event.** A UI event is an intent → it maps to a `Command`. A domain
  event is a fact the aggregate emitted → the UI neither creates nor consumes it directly.
- **Bloc State ≠ Decider State.** UI state is what the screen shows, built from the **read
  side** (a `View`/`MaterializedView` projection). Decider state is the **write side**'s
  internal fold target. Different shape, different owner, different lifetime.
- **Bloc Transition ≠ `evolve`.** Bloc's `Transition` is `(oldUiState, uiEvent, newUiState)`,
  a presentation-layer bookkeeping record. `evolve(state, event)` is the domain's pure
  event-sourced fold. Unrelated concepts that happen to share the word "transition".

## 2. Exactly what to rename — and what to leave alone

**Rename these two (presentation layer only):**

| Before | After |
| --- | --- |
| `class AddItemEvent` (bloc) | `class AddItemUiEvent` (sealed base) with a concrete case named after the intent, e.g. `AddItemSubmitted` |
| `class AddItemState` (bloc) | `class AddItemUiState` |

**Leave these two exactly as they are — do not touch them:**

- `ItemAddedEvent` (the decider's domain event) — it's a fact, correctly named, owned by the
  domain layer.
- `AddItemState` (the decider's write-model state) — it's the Decider's internal fold target,
  correctly named, owned by the domain layer.

The rule that decides which side moves: **the domain layer keeps the names fmodel already
gives it; every presentation-layer type gets a `Ui` marker added.** Never rename a domain type
to resolve a collision — that only pushes the ambiguity onto the layer that's supposed to be
the stable, well-understood one. The `Ui` marker on the *bloc's* types is the fix, always.

Don't stop at the class names — rename the concrete UI-event case to describe the *intent*,
not the fact. A case called `ItemAdded` (past tense, sounds like a fact) is itself a smaller
version of the same collision; call it `AddItemSubmitted` so its name can never be confused
with `ItemAddedEvent`.

## 3. The bug: the bloc is constructing the domain event itself

You said the `AddItemEvent` handler "constructs the domain `ItemAddedEvent` directly" — that
is wrong, and it's not a style nitpick, it breaks the architecture:

- `ItemAddedEvent` is supposed to be a fact **only the Decider's `decide()` function is allowed
  to produce**, after it has validated the command against current state. If the bloc
  constructs `ItemAddedEvent` itself, it is bypassing all of the decider's business rules and
  putting a "fact" into the system that the domain never actually decided happened.
- The bloc's only legitimate output toward the domain is a **`Command`** (`AddItemCommand`).
  The command is an *intent* that can be rejected; only the aggregate (which runs
  `decide → evolve → persist`) gets to turn it into `ItemAddedEvent`(s), or into a
  `DomainError` if it's invalid.
- Symmetrically, the bloc must not read the write-side `AddItemState` either. Its `UiState`
  should be built from the **read side** — a `View`/`MaterializedView` projection — never from
  the Decider's internal state.

So there are two bugs stacked on each other: constructing a domain event directly, and (very
likely, given a bare `AddItemState` in the bloc file too) rendering off write-model state
instead of a read-model projection.

## 4. The corrected flow

One UI intent, five steps, always in this order:

```
widget → AddItemSubmitted (UiEvent)
       → AddItemCommand                         (bloc builds this — never ItemAddedEvent)
       → service.handle(command)                (aggregate: decide → evolve → persist)
       → service.wardrobe()                      (read the View projection, not Decider state)
       → emit(AddItemUiState(status, wardrobe))  (never the raw AddItemState)
```

See the corrected code in this directory:

- `add_item_ui_event.dart` — the sealed `AddItemUiEvent` hierarchy (`AddItemSubmitted`).
- `add_item_ui_state.dart` — `AddItemUiState` + `AddItemStatus`, built from the read-model
  `WardrobeViewState`, never from the decider's `AddItemState`.
- `add_item_bloc.dart` — the `AddItemBloc`, which builds `AddItemCommand` from the intent,
  calls the application service, and emits `AddItemUiState` from the fresh view projection.
  It imports `AddItemCommand`, `WardrobeViewState`, and `DomainError` from the domain/
  application layer — it never redefines them, and it never touches `ItemAddedEvent` or the
  decider's `AddItemState` at all.

## 5. The reusable rule

Apply this to every screen, not just this one:

> **The domain layer keeps the names fmodel gives it. Every presentation-layer type — every
> bloc/cubit event, state, and status — carries a `Ui` marker.** A bare `<X>Event` or
> `<X>State` is never allowed in a bloc/cubit file; if you see one, that's the ambiguity this
> rule exists to remove.

Concretely, for any `<UseCase>` screen:

| Kind | Owner | Convention | Example |
| --- | --- | --- | --- |
| command | domain | `<UseCase>Command` | `AddItemCommand` |
| domain event (fact) | domain | `<Fact>Event`, past tense | `ItemAddedEvent` |
| write-model state | domain | `<UseCase>State` | `AddItemState` |
| read-model state | domain | `<ReadModel>ViewState` | `WardrobeViewState` |
| UI event (intent) | presentation | `<Screen>UiEvent` (sealed), cases named as intents | `AddItemUiEvent` → `AddItemSubmitted` |
| UI state | presentation | `<Screen>UiState` + `<Screen>Status` | `AddItemUiState` |

And two invariants that go with the naming rule, enforced in code review, not just in names:

1. **A `UiEvent` handler never constructs or emits a domain `Event`.** It builds a `Command`
   and calls the application/service layer; the Decider alone decides which events, if any,
   result.
2. **A `UiState`'s render data always comes from the read-side projection, never from the
   Decider's write-model state.** If a bloc/cubit file imports/uses the write-model `State`
   type at all, that's a defect — the write side is internal to the aggregate.

If you keep those two invariants and the `Ui`-marker naming rule, `AddItemEvent` vs.
`ItemAddedEvent` and `AddItemState` vs. `AddItemState` stop being an ambiguity anyone has to
puzzle over in review — the name alone tells you which layer and which concept you're looking
at.
