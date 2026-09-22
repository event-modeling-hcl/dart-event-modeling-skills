# Naming and Layers

This is the conceptual core of the `fmodel_bloc` skill. It defines the vocabulary, the naming
rules, and the layer boundaries that keep an fmodel + bloc codebase readable. When a name or a
boundary is in doubt, this file decides.

## Table of contents

1. Why the collision happens
2. The collision glossary
3. Naming rules
4. The layers and what each owns
5. Import direction and dependency injection
6. Worked vocabulary: the Wardrobe example
7. Anti-patterns

## 1. Why the collision happens

fmodel is a functional domain-modelling library. Its `Decider<C, S, E>` is defined by two pure
functions:

```dart
typedef Decide<C, S, E> = Stream<E> Function(C command, S state);   // handle intent -> facts
typedef Evolve<S, E>    = S Function(S state, E event);             // fold a fact into state
```

bloc is a presentation-layer state-management library. Its `Bloc<Event, State>` turns UI
**events** into UI **states** through registered handlers:

```dart
on<CounterIncrementPressed>((event, emit) => emit(state + 1));
```

Both libraries legitimately own the words **event** and **state**, and both describe a
**transition** from one state to the next. The words are the same; the referents are not. A
developer reading `AddItemEvent` cannot tell whether it is a fact the aggregate emitted or a
button the user pressed. That ambiguity, multiplied across a codebase, is the muddiness this
skill removes.

## 2. The collision glossary

Learn these six terms; every naming rule follows from them.

| Term | Where | Precise meaning | Example |
| --- | --- | --- | --- |
| **Command** | fmodel | An intent to change state; input to `decide`. May be rejected. | `AddItemCommand` |
| **Domain Event** | fmodel | A fact that already happened; output of `decide`, input to `evolve`. Immutable, past tense. | `ItemAddedEvent` |
| **Decider State** | fmodel | The write-model reconstructed by folding domain events with `evolve`. Internal to the command side. | `AddItemState` |
| **View State** | fmodel | The read-model / query projection, also folded from events by a `View`. What the UI reads. | `WardrobeViewState` |
| **UI Event** | bloc | A user (or system) intent expressed to a `Bloc`; a request, not a fact. | `AddItemUiEvent` |
| **UI State** | bloc | The immutable snapshot a widget renders: read-model data + a status. | `AddItemUiState` |

The three equalities that must never blur:

- **Bloc Event ≠ Domain Event.** A UI event is an intent → it maps to a `Command`. A domain
  event is a fact the aggregate emitted → the UI never constructs one and rarely reads one
  directly (it reads the View projection instead).
- **Bloc State ≠ Aggregate/Decider State.** UI state is what the screen shows. Decider state is
  the write-model. They have different shapes, different lifetimes, and different owners.
- **Bloc Transition ≠ `evolve`.** A bloc `Transition`/`Change` is `(oldUiState, uiEvent,
  newUiState)` in the presentation layer. `evolve(state, event)` is a pure fold of a *domain*
  event into *domain* state. Different layer, different types.

## 3. Naming rules

The rule in one sentence: **domain types keep the names fmodel and the upstream
`map-event-model-hcl-to-code` skill already give them; every presentation type carries a `Ui`
marker.**

| Layer | Kind | Convention | Example |
| --- | --- | --- | --- |
| domain | command | `<UseCase>Command` | `AddItemCommand`, `RemoveItemCommand` |
| domain | domain event (fact) | `<Fact>Event`, past tense | `ItemAddedEvent`, `ItemRemovedEvent` |
| domain | domain event base | `<Context>Event` (sealed) | `WardrobeEvent` |
| domain | write-model state | `<UseCase>State` | `AddItemState` |
| domain | read-model state | `<ReadModel>ViewState` | `WardrobeViewState` |
| domain | domain error base | `DomainError` (sealed) | `ItemAlreadyExistsError` |
| presentation | UI event (intent) | `<Screen>UiEvent` (sealed) | `AddItemUiEvent` |
| presentation | UI event case | verb + `Requested`/`Pressed`/`Submitted` | `AddItemSubmitted` |
| presentation | UI state | `<Screen>UiState` | `AddItemUiState` |
| presentation | UI status enum | `<Screen>Status` | `AddItemStatus` |
| presentation | cubit / bloc | `<Screen>Cubit` / `<Screen>Bloc` | `AddItemCubit` |

Rules:

- **Never** write a bare `AddItemEvent` / `AddItemState` in the presentation layer. The absent
  `Ui` is the ambiguity this skill exists to remove.
- **Never** rename a domain type to resolve a collision. Add the `Ui` marker on the presentation
  side. Renaming domain types diverges this skill from `map-event-model-hcl-to-code`, which is
  the source of those names.
- UI **events** name the *intent* (`AddItemSubmitted`, `SearchQueryChanged`), not the fact.
  Domain **events** name the *fact* (`ItemAddedEvent`). If a UI-event name reads like a fact,
  it is misnamed.
- UI **states** are nouns with a status. Prefer a single `<Screen>UiState` class carrying a
  `<Screen>Status` enum (`initial | loading | success | failure`) over a sealed hierarchy of
  one-class-per-status, so partial data (e.g. a cached projection during `loading`) is easy to
  keep. Either idiom is acceptable; be consistent within a screen.

## 4. The layers and what each owns

Four layers, top to bottom. This skill only writes the top two.

- **widgets** — Flutter `Widget`s. Read `UiState` via `BlocBuilder`/`BlocSelector`, react to it
  via `BlocListener`, and send intents (`context.read<AddItemCubit>().addItem(...)` or
  `context.read<AddItemBloc>().add(AddItemSubmitted(...))`). Widgets know only the presentation
  layer.
- **presentation** *(this skill)* — `Cubit`/`Bloc` classes plus their `UiState`/`UiEvent` types.
  Translate intents to `Command`s, invoke the application layer, project read-model data into
  `UiState`. Hold no persistence and no domain rules.
- **application** *(owned by fmodel / upstream skill)* — aggregates and services:
  `EventSourcingAggregate`, `StateStoredAggregate`, `MaterializedView`, `EphemeralView`,
  `SagaManager`, and the repository *ports* they depend on. `handle(command)` /
  `handle(event)` live here.
- **domain** *(owned by fmodel / upstream skill)* — pure `Decider<C,S,E>`, `View<S,E>`,
  `Saga<AR,A>`, commands, domain events, states, value objects. No I/O.

## 5. Import direction and dependency injection

Imports point strictly downward: `widgets → presentation → application → domain`. A domain file
that imports a bloc is a defect; a bloc that imports a Flutter widget is a defect.

- The presentation layer depends on an **application service or aggregate**, received through its
  constructor — never constructed inside the Cubit/Bloc. This keeps the presentation layer
  testable with a fake service.
- Inject the service into the widget tree with `RepositoryProvider` (from flutter_bloc), then
  read it in the `BlocProvider`'s `create`:

  ```dart
  RepositoryProvider<WardrobeService>(
    create: (_) => WardrobeService(aggregate, view),
    child: BlocProvider(
      create: (ctx) => AddItemCubit(ctx.read<WardrobeService>()),
      child: const AddItemView(),
    ),
  )
  ```

- fmodel repositories are **ports**; their adapters (over a platform `EventStore`) already live
  in the domain/application slices produced upstream. The presentation layer never touches a
  repository directly — only the service/aggregate façade.

## 6. Worked vocabulary: the Wardrobe example

A single "add an item to my wardrobe" feature, fully named:

| Concept | Type |
| --- | --- |
| user taps "Add" | `AddItemSubmitted` (a case of `AddItemUiEvent`) — bloc path only |
| what the screen renders | `AddItemUiState` (`status`, `wardrobe`, `error`) |
| the intent as domain input | `AddItemCommand(name, category)` |
| the fact the aggregate emits | `ItemAddedEvent(itemId, name, category)` |
| write-model folded from facts | `AddItemState` |
| read-model the screen reads | `WardrobeViewState(items)` |
| the presentation object | `AddItemCubit` or `AddItemBloc` |

Reading any one name tells you exactly which layer and which concept you are looking at.

## 7. Anti-patterns

- `class AddItemEvent` in a bloc file — is it the intent or the fact? Rename to `AddItemUiEvent`.
- A `UiState` that embeds the Decider state (`AddItemState`) as its render data — couples the UI
  to the write-model. Render the `WardrobeViewState` projection instead.
- A Cubit/Bloc that constructs an aggregate or opens the event store itself — inject the service.
- Mapping a `UiEvent` directly to a domain `Event` (`emit`ting `ItemAddedEvent`) — the UI issues
  a `Command`; the aggregate decides which domain events result.
- Renaming `ItemAddedEvent` to `ItemAddedDomainEvent` to avoid collision — unnecessary and it
  diverges from the upstream skill. The `Ui` marker on the presentation side is the fix.
