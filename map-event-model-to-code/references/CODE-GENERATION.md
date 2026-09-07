# Dart Code Generation Rules

This reference covers generating a Dart app skeleton from an Event Model table.
Generated code uses `fmodel-dart`, `package:fmodel/fmodel.dart`, and
`package:test`.

The output should be platform-neutral Dart. Generate in-memory repositories for
runnable demos. Do not choose HTTP, database, queue, or deployment technology
unless the user explicitly asks for it.

## 1. Package Shape

For a new generated project, create the usual Dart package files and this code
layout:

```text
pubspec.yaml
analysis_options.yaml
lib/
  domain.dart
  application.dart
  infrastructure.dart
  fmodel.dart
  src/
    domain/
      api.dart
      deciders/
        {use_case}_decider.dart
      views/
        {entity}_view.dart
    application/
      {use_case}_aggregate.dart
      {entity}_materialized_view.dart
    infrastructure/
      memory/
        {use_case}_event_repository.dart
        {entity}_view_repository.dart
test/
  fixtures.dart
  support/
    decider_test_dsl.dart
    view_test_dsl.dart
  domain/
    {use_case}_decider_test.dart
    {entity}_view_test.dart
  application/
    {use_case}_aggregate_test.dart
    {entity}_materialized_view_test.dart
```

Use the same shape inside an existing Dart package, adapting names to local
conventions and preserving existing barrel files.

Minimum `pubspec.yaml` dependencies:

```yaml
environment:
  sdk: ^3.10.0

dependencies:
  fmodel: any

dev_dependencies:
  lints: ^6.0.0
  test: ^1.31.2
```

When generating inside a repo that already depends on `fmodel`, preserve its
declared version or path dependency.

## 2. Shared Domain API

Generate shared domain types in `lib/src/domain/api.dart`.

### IDs and Value Objects

Prefer extension types for simple scalar wrappers:

```dart
extension type const RestaurantId._(String value) {
  factory RestaurantId(String raw) => RestaurantId._(raw);

  @override
  String toString() => value;
}

extension type const RestaurantName._(String value) {
  factory RestaurantName(String raw) => RestaurantName._(raw);
}
```

Use small immutable classes when a value object has multiple fields or behavior:

```dart
final class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
  });

  final MenuItemId id;
  final MenuItemName name;
  final Money price;
}
```

Rules:

- Create one ID type for each unique entity identifier.
- Use `PascalCaseId` names such as `RestaurantId` and `OrderId`.
- Use immutable fields and `const` constructors wherever practical.
- Add equality/hashCode only when classes will be compared in tests and records
  or extension types are not enough.

### Domain Errors

Use Dart exception types for invariant violations:

```dart
sealed class DomainError implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  String toString() => message;
}

final class RestaurantAlreadyExistsError extends DomainError {
  const RestaurantAlreadyExistsError(this.restaurantId)
    : super('Restaurant already exists.');

  final RestaurantId restaurantId;
}
```

Common patterns:

- `{Entity}AlreadyExistsError` for create commands when state already exists.
- `{Entity}NotFoundError` for commands that require existing state.
- `{Entity}Already{Status}Error` for idempotent target-state commands when the
  business wants an error instead of no-op behavior.
- `{Entity}Not{Status}Error` for commands that require a prerequisite state.
- `{Thing}NotAvailableError` for validation against related state.

### Commands

Model commands as sealed hierarchies:

```dart
sealed class RestaurantCommand {
  const RestaurantCommand();
}

final class CreateRestaurant extends RestaurantCommand {
  const CreateRestaurant({
    required this.restaurantId,
    required this.name,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;
}

final class ChangeRestaurantMenu extends RestaurantCommand {
  const ChangeRestaurantMenu({
    required this.restaurantId,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantMenu menu;
}
```

Rules:

- Create one command class per command cell.
- Name classes in imperative form from the sticky note.
- Group commands under an aggregate-specific sealed superclass when they share
  state and event streams.

### Events

Model events as sealed hierarchies:

```dart
sealed class RestaurantEvent {
  const RestaurantEvent();
}

final class RestaurantCreated extends RestaurantEvent {
  const RestaurantCreated({
    required this.restaurantId,
    required this.name,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;
}

final class RestaurantMenuChanged extends RestaurantEvent {
  const RestaurantMenuChanged({
    required this.restaurantId,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantMenu menu;
}
```

Rules:

- Create one event class per event cell.
- Event class names should be past-tense facts.
- Do not add runtime tag-field metadata by default. In-memory repositories route
  events by inspecting typed fields.
- If an event participates in multiple aggregate streams, include all relevant
  identifier fields as typed properties.

### State

Derive command-side state from invariants and view state from projections:

```dart
enum RestaurantStatus { active, closed }

final class Restaurant {
  const Restaurant({
    required this.restaurantId,
    required this.name,
    required this.menu,
    required this.status,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;
  final RestaurantStatus status;

  Restaurant copyWith({
    RestaurantName? name,
    RestaurantMenu? menu,
    RestaurantStatus? status,
  }) {
    return Restaurant(
      restaurantId: restaurantId,
      name: name ?? this.name,
      menu: menu ?? this.menu,
      status: status ?? this.status,
    );
  }
}
```

Use nullable state (`Restaurant?`) when an entity can be absent. Use records for
small combined state only when named classes would not add clarity.

## 3. Deciders

Generate one `Decider<C, S, E>` for each command or cohesive command group.
Import only the domain library if application APIs are not needed:

```dart
import 'package:fmodel/domain.dart';

import '../api.dart';

Decider<RestaurantCommand, Restaurant?, RestaurantEvent> restaurantDecider() {
  return Decider(
    initialState: null,
    decide: (command, state) async* {
      switch (command) {
        case CreateRestaurant():
          if (state != null) {
            return;
          }
          yield RestaurantCreated(
            restaurantId: command.restaurantId,
            name: command.name,
            menu: command.menu,
          );
        case ChangeRestaurantMenu():
          if (state == null) {
            throw RestaurantNotFoundError(command.restaurantId);
          }
          yield RestaurantMenuChanged(
            restaurantId: command.restaurantId,
            menu: command.menu,
          );
      }
    },
    evolve: (state, event) {
      return switch (event) {
        RestaurantCreated() => Restaurant(
          restaurantId: event.restaurantId,
          name: event.name,
          menu: event.menu,
          status: RestaurantStatus.active,
        ),
        RestaurantMenuChanged() => state?.copyWith(menu: event.menu),
      };
    },
  );
}
```

Mapping rules:

- Command type `C`: use a specific command class for a single-command decider,
  or the sealed command superclass for a cohesive aggregate.
- State type `S`: derive the minimal state required for validation.
- Event type `E`: include all events needed by `evolve` to reconstruct state and
  all events emitted by `decide`.
- Initial state: use `null` for missing aggregate state or a concrete empty
  state object for counters, carts, and other always-present models.
- Idempotent duplicate commands: emit no events by returning from the `async*`
  body or using `yield* const Stream<Event>.empty()`.
- Invalid commands: throw a typed `DomainError` only when the model says the
  action is invalid rather than already applied.

Use Dart pattern matching in `switch` statements. Keep `decide` free of storage,
transport, clock, random, and framework concerns.

## 4. Views

For each unique Event Modeling projection, generate a `View<S, E>` in
`lib/src/domain/views/{entity}_view.dart`.

```dart
import 'package:fmodel/domain.dart';

import '../api.dart';

final class RestaurantViewState {
  const RestaurantViewState({
    required this.restaurantId,
    required this.name,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;

  RestaurantViewState copyWith({RestaurantMenu? menu}) {
    return RestaurantViewState(
      restaurantId: restaurantId,
      name: name,
      menu: menu ?? this.menu,
    );
  }
}

View<RestaurantViewState?, RestaurantEvent> restaurantView() {
  return View(
    initialState: null,
    evolve: (state, event) {
      return switch (event) {
        RestaurantCreated() => RestaurantViewState(
          restaurantId: event.restaurantId,
          name: event.name,
          menu: event.menu,
        ),
        RestaurantMenuChanged() => state?.copyWith(menu: event.menu),
      };
    },
  );
}
```

Mapping rules:

- Collect all formulas where the projection appears on the left side of `<-`.
- The view event type `E` is the union superclass covering those events.
- The first creation event usually returns a new state object.
- Subsequent events update existing state with `copyWith` and preserve state
  when the projection has not been created.
- The initial state is usually `null` for entity lookups and an empty collection
  for list/search projections.

## 5. Application Factories

Generate thin application factories around the domain components and repository
contracts.

### Event-Sourcing Aggregate

```dart
import 'package:fmodel/fmodel.dart';

import '../domain/api.dart';

typedef RestaurantAggregate = EventSourcingAggregate<
  RestaurantCommand,
  Restaurant?,
  RestaurantEvent,
  NoMetadata,
  NoMetadata
>;

RestaurantAggregate restaurantAggregate({
  required DeciderContract<RestaurantCommand, Restaurant?, RestaurantEvent>
  decider,
  required EventRepository<
    RestaurantCommand,
    RestaurantEvent,
    NoMetadata,
    NoMetadata
  >
  eventRepository,
}) {
  return createEventSourcingAggregate(
    decider: decider,
    eventRepository: eventRepository,
  );
}
```

### Materialized View

```dart
import 'package:fmodel/fmodel.dart';

import '../domain/api.dart';
import '../domain/views/restaurant_view.dart';

typedef RestaurantMaterializedView = MaterializedView<
  RestaurantViewState?,
  RestaurantEvent,
  NoMetadata
>;

RestaurantMaterializedView restaurantMaterializedView({
  required View<RestaurantViewState?, RestaurantEvent> view,
  required ViewStateRepository<
    RestaurantEvent,
    RestaurantViewState?,
    NoMetadata
  >
  viewStateRepository,
}) {
  return createMaterializedView(
    view: view,
    viewStateRepository: viewStateRepository,
  );
}
```

Rules:

- Application files import `package:fmodel/fmodel.dart`.
- Keep factories thin; validation belongs in deciders and state projection
  belongs in views.
- Use `NoMetadata` by default. Add metadata type parameters only when the user
  asks for metadata-aware handling.

## 6. In-Memory Infrastructure

Generate demo repositories in `lib/src/infrastructure/memory/`. They should be
small, deterministic implementations of `EventRepository` and
`ViewStateRepository`.

### Event Repository

```dart
import 'package:fmodel/fmodel.dart';

import '../../domain/api.dart';

final class MemoryRestaurantEventRepository
    with EventRepositoryDefaults<RestaurantCommand, RestaurantEvent>
    implements
        EventRepository<
          RestaurantCommand,
          RestaurantEvent,
          NoMetadata,
          NoMetadata
        > {
  MemoryRestaurantEventRepository([Map<RestaurantId, List<RestaurantEvent>>? events])
    : _events = events ?? {};

  final Map<RestaurantId, List<RestaurantEvent>> _events;

  @override
  Stream<RestaurantEvent> fetchEvents(RestaurantCommand command) {
    return Stream.fromIterable(_events[_restaurantIdOf(command)] ?? const []);
  }

  @override
  Stream<RestaurantEvent> save(Stream<RestaurantEvent> events) async* {
    await for (final event in events) {
      final restaurantId = _restaurantIdOfEvent(event);
      _events.putIfAbsent(restaurantId, () => <RestaurantEvent>[]).add(event);
      yield event;
    }
  }

  RestaurantId _restaurantIdOf(RestaurantCommand command) {
    return switch (command) {
      CreateRestaurant() => command.restaurantId,
      ChangeRestaurantMenu() => command.restaurantId,
    };
  }

  RestaurantId _restaurantIdOfEvent(RestaurantEvent event) {
    return switch (event) {
      RestaurantCreated() => event.restaurantId,
      RestaurantMenuChanged() => event.restaurantId,
    };
  }
}
```

### View State Repository

```dart
import 'package:fmodel/fmodel.dart';

import '../../domain/api.dart';
import '../../domain/views/restaurant_view.dart';

final class MemoryRestaurantViewRepository
    with ViewStateRepositoryDefaults<RestaurantEvent, RestaurantViewState?>
    implements
        ViewStateRepository<
          RestaurantEvent,
          RestaurantViewState?,
          NoMetadata
        > {
  RestaurantViewState? _state;

  @override
  Future<RestaurantViewState?> fetchState(RestaurantEvent event) async {
    return _state;
  }

  @override
  Future<RestaurantViewState?> save(RestaurantViewState? state) async {
    _state = state;
    return _state;
  }
}
```

Rules:

- Route event streams by typed identifier fields inferred from command and event
  classes.
- Use one repository per aggregate stream or view state shape.
- Keep repositories simple and local to demos. Do not imply production storage
  semantics.

## 7. Tests

Use `package:test`.

### Optional Decider Test DSL

Generate this helper when there are several decider tests:

```dart
import 'package:fmodel/domain.dart';
import 'package:test/test.dart';

extension DeciderTestDsl<C, S, E> on Decider<C, S, E> {
  GivenEventsWhenStep<C, S, E> givenEvents(Iterable<E> events) {
    return GivenEventsWhenStep(this, events);
  }
}

final class GivenEventsWhenStep<C, S, E> {
  const GivenEventsWhenStep(this._decider, this._events);

  final Decider<C, S, E> _decider;
  final Iterable<E> _events;

  GivenEventsThenStep<C, S, E> whenCommand(C command) {
    return GivenEventsThenStep(_decider, _events, command);
  }
}

final class GivenEventsThenStep<C, S, E> {
  const GivenEventsThenStep(this._decider, this._events, this._command);

  final Decider<C, S, E> _decider;
  final Iterable<E> _events;
  final C _command;

  Future<void> thenEvents(Iterable<E> expected) async {
    final state = _events.fold<S>(
      _decider.initialState,
      (state, event) => _decider.evolve(state, event),
    );
    final actual = await _decider.decide(_command, state).toList();
    expect(actual, expected);
  }
}
```

### Optional View Test DSL

```dart
import 'package:fmodel/domain.dart';
import 'package:test/test.dart';

extension ViewTestDsl<S, E> on View<S, E> {
  void givenEventsThenState(Iterable<E> events, S expected) {
    final actual = events.fold<S>(
      initialState,
      (state, event) => evolve(state, event),
    );
    expect(actual, expected);
  }
}
```

### Decider Tests

```dart
import 'package:test/test.dart';

import '../../lib/src/domain/deciders/restaurant_decider.dart';
import '../fixtures.dart';
import '../support/decider_test_dsl.dart';

void main() {
  group('restaurantDecider', () {
    test('creates a restaurant when none exists', () async {
      await restaurantDecider()
          .givenEvents(const <RestaurantEvent>[])
          .whenCommand(createRestaurant)
          .thenEvents([restaurantCreated]);
    });

    test('does not create the same restaurant twice', () async {
      await restaurantDecider()
          .givenEvents([restaurantCreated])
          .whenCommand(createRestaurant)
          .thenEvents(const <RestaurantEvent>[]);
    });
  });
}
```

For errors, use `expectLater` against the event stream:

```dart
await expectLater(
  restaurantDecider().decide(changeMissingRestaurantMenu, null),
  emitsError(isA<RestaurantNotFoundError>()),
);
```

### Application Tests

Test aggregate and materialized-view factories with generated memory
repositories:

```dart
test('aggregate persists emitted events', () async {
  final aggregate = restaurantAggregate(
    decider: restaurantDecider(),
    eventRepository: MemoryRestaurantEventRepository(),
  );

  await expectLater(
    aggregate.handle(createRestaurant),
    emitsInOrder([restaurantCreated, emitsDone]),
  );
});
```

## 8. Fixtures

Generate shared fixtures in `test/fixtures.dart`:

```dart
import '../lib/src/domain/api.dart';

final restaurantId = RestaurantId('restaurant-1');
final restaurantName = RestaurantName('Test Restaurant');
final restaurantMenu = RestaurantMenu(items: [menuItem]);

final createRestaurant = CreateRestaurant(
  restaurantId: restaurantId,
  name: restaurantName,
  menu: restaurantMenu,
);

final restaurantCreated = RestaurantCreated(
  restaurantId: restaurantId,
  name: restaurantName,
  menu: restaurantMenu,
);
```

Rules:

- Keep fixtures small and deterministic.
- Reuse fixtures across decider, view, aggregate, and materialized-view tests.
- Fixture events must exactly match the events produced by deciders.

## 9. Barrel Exports

Export generated API surfaces through concise barrels:

```dart
// lib/domain.dart
library;

export 'src/domain/api.dart';
export 'src/domain/deciders/restaurant_decider.dart';
export 'src/domain/views/restaurant_view.dart';
```

```dart
// lib/application.dart
library;

export 'src/application/restaurant_aggregate.dart';
export 'src/application/restaurant_materialized_view.dart';
```

```dart
// lib/infrastructure.dart
library;

export 'src/infrastructure/memory/restaurant_event_repository.dart';
export 'src/infrastructure/memory/restaurant_view_repository.dart';
```

```dart
// lib/fmodel.dart
library;

export 'application.dart';
export 'domain.dart';
export 'infrastructure.dart';
```

## 10. Workflow

1. Parse the user's Event Model diagram into a table, formulas, and Mermaid
   diagram.
2. Confirm or refine the table before generating code when the diagram is
   ambiguous.
3. Generate the shared domain API.
4. Generate deciders and views from the command/event/projection formulas.
5. Generate fixtures and tests.
6. Generate application factories and in-memory repositories.
7. Update barrel exports.
8. Run `dart format .`, `dart analyze`, and `dart test` when working in a
   generated Dart package.

Preserve existing project conventions when adding to an existing package.
