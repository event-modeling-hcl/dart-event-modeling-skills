# Dart Vertical-Slice Code Generation

This reference covers generating Dart code from an Event Model table. Generated
code uses `fmodel-dart`, `package:fmodel/fmodel.dart`, and `package:test`.

The generated architecture is vertical-slice oriented:

- Shared domain contracts live under `bounded_contexts`.
- Concrete slices live under the top-level `state_change`, `state_view`,
  `automation`, and `translation` folders.
- Generic runtime and adapter infrastructure lives under `platform`.
- Cross-slice wiring lives under `composition`.

The four slice category folders are direct children of `lib/`. Do not nest them
inside bounded contexts.

## 1. Target Package Shape

For a new generated package, create this structure:

```text
pubspec.yaml
analysis_options.yaml
lib/
  bounded_contexts/
    <bounded_context>/
      api.dart
      value_objects.dart
      events.dart
      event_tags.dart
      serialization.dart
  state_change/
    <use_case>/
      command.dart
      state.dart
      errors.dart
      decider.dart
      repository.dart
      aggregate.dart
      service.dart
      handler.dart
      dto.dart
      serialization.dart
      module.dart
      ui/
  state_view/
    <read_model>/
      query.dart
      state.dart
      view.dart
      repository.dart
      service.dart
      handler.dart
      dto.dart
      module.dart
      ui/
  automation/
    <process_or_policy>/
      saga.dart
      publisher.dart
      service.dart
      handler.dart
      module.dart
  translation/
    <external_boundary>/
      dto.dart
      mapper.dart
      codec.dart
      port.dart
      adapter.dart
      handler.dart
      module.dart
  composition/
    app_services.dart
    slice_registry.dart
    vertical_slice.dart
  platform/
    event_store/
    server/
test/
  bounded_contexts/
  state_change/
  state_view/
  automation/
  translation/
  platform/
```

Only create concrete slice files that the model or user request calls for. For
new repositories, create all four top-level category folders; if a category is
empty and must be tracked in git, add a `.gitkeep`.

Minimum `pubspec.yaml` requirements:

```yaml
environment:
  sdk: ^3.10.0

dependencies:
  fmodel: any

dev_dependencies:
  lints: ^6.0.0
  test: ^1.31.2
```

When generating inside an existing Dart package, preserve its dependency
versions, existing platform adapters, and existing composition conventions.

## 2. Mapping Event Model Concepts

Map the table formulas into top-level folders:

| Event Model element | Generated folder | Generated slice |
| ------------------- | ---------------- | --------------- |
| Command with produced events | `state_change/<use_case>/` | A command-handling slice |
| Projection/read model | `state_view/<read_model>/` | A query or read-model slice |
| Event-to-command policy/process | `automation/<process_or_policy>/` | A saga/process slice |
| External command, event, or DTO boundary | `translation/<external_boundary>/` | A boundary translation slice |
| Domain event/value object vocabulary | `bounded_contexts/<bounded_context>/` | Shared cross-slice contracts |

Each slice imports one or more bounded-context APIs explicitly. Do not infer
bounded-context ownership from folder nesting because slice folders are
top-level category folders.

If slice names would collide across bounded contexts, prefix the slice folder
name with the bounded-context name, for example `restaurant_create` or
`ordering_create`.

## 3. Bounded Contexts

Each bounded context owns shared domain contracts only:

```text
lib/bounded_contexts/restaurant/
  api.dart
  value_objects.dart
  events.dart
  event_tags.dart
  serialization.dart
```

Do not place commands, deciders, handlers, services, UI, repositories, or
slice-local errors in bounded-context folders.

### `value_objects.dart`

Use extension types for simple scalar wrappers and immutable classes for
compound values:

```dart
extension type const RestaurantId._(String value) {
  factory RestaurantId(String raw) {
    if (raw.isEmpty) throw ArgumentError('RestaurantId cannot be empty');
    return RestaurantId._(raw);
  }
}

extension type const RestaurantName._(String value) {
  factory RestaurantName(String raw) => RestaurantName._(raw);
}

final class MenuItem {
  const MenuItem({
    required this.menuItemId,
    required this.name,
    required this.price,
  });

  final MenuItemId menuItemId;
  final MenuItemName name;
  final MenuItemPrice price;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MenuItem &&
            menuItemId == other.menuItemId &&
            name == other.name &&
            price == other.price;
  }

  @override
  int get hashCode => Object.hash(menuItemId, name, price);
}
```

### `events.dart`

Use sealed event hierarchies and final event classes:

```dart
import 'value_objects.dart';

sealed class RestaurantEvent {
  const RestaurantEvent();
}

final class RestaurantCreatedEvent extends RestaurantEvent {
  const RestaurantCreatedEvent({
    required this.restaurantId,
    required this.name,
    required this.menu,
    this.isFinal = true,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;
  final bool isFinal;
}

final class RestaurantMenuChangedEvent extends RestaurantEvent {
  const RestaurantMenuChangedEvent({
    required this.restaurantId,
    required this.menu,
    this.isFinal = true,
  });

  final RestaurantId restaurantId;
  final RestaurantMenu menu;
  final bool isFinal;
}
```

When multiple bounded contexts share one event store, generate a minimal shared
event supertype under `lib/bounded_contexts/` and have each bounded-context event
base implement it. Keep that supertype free of infrastructure concerns.

### `event_tags.dart`

Generate tag extraction next to the events:

```dart
import 'events.dart';

typedef EventTag = ({String tag, String value});

String restaurantEventTypeName(RestaurantEvent event) {
  return switch (event) {
    RestaurantCreatedEvent() => 'RestaurantCreatedEvent',
    RestaurantMenuChangedEvent() => 'RestaurantMenuChangedEvent',
  };
}

List<EventTag> restaurantEventTags(RestaurantEvent event) {
  return switch (event) {
    RestaurantCreatedEvent(:final restaurantId) => [
      (tag: 'restaurantId', value: restaurantId.value),
    ],
    RestaurantMenuChangedEvent(:final restaurantId) => [
      (tag: 'restaurantId', value: restaurantId.value),
    ],
  };
}
```

Events that identify multiple entities should return all relevant tags. The
platform event store may index all non-empty tag subsets.

### `serialization.dart`

Put shared event encode/decode helpers in the bounded context when they are
stable domain contracts. If a codec is only needed by a specific external
boundary, put it in `translation/<external_boundary>/` instead.

### `api.dart`

Export the context contract:

```dart
library;

export 'value_objects.dart';
export 'events.dart';
export 'event_tags.dart';
export 'serialization.dart';
```

## 4. State Change Slices

Generate one state-change slice for each command cell or cohesive command group:

```text
lib/state_change/create_restaurant/
  command.dart
  state.dart
  errors.dart
  decider.dart
  repository.dart
  aggregate.dart
  service.dart
  handler.dart
  dto.dart
  serialization.dart
  module.dart
```

The slice owns all command-specific behavior end to end.

### Command, State, Errors

```dart
// command.dart
import '../../bounded_contexts/restaurant/api.dart';

final class CreateRestaurantCommand {
  const CreateRestaurantCommand({
    required this.restaurantId,
    required this.name,
    required this.menu,
  });

  final RestaurantId restaurantId;
  final RestaurantName name;
  final RestaurantMenu menu;
}
```

```dart
// state.dart
import '../../bounded_contexts/restaurant/api.dart';

final class CreateRestaurantState {
  const CreateRestaurantState({this.restaurantId});

  final RestaurantId? restaurantId;

  bool get exists => restaurantId != null;
}
```

```dart
// errors.dart
import '../../bounded_contexts/restaurant/api.dart';

sealed class DomainError implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class RestaurantAlreadyExistsError extends DomainError {
  const RestaurantAlreadyExistsError(this.restaurantId)
    : super('Restaurant already exists');

  final RestaurantId restaurantId;
}
```

Keep errors in the slice unless the same error is part of a stable cross-slice
domain contract.

### Decider

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import 'command.dart';
import 'errors.dart';
import 'state.dart';

final createRestaurantDecider =
    Decider<CreateRestaurantCommand, CreateRestaurantState, RestaurantEvent>(
  initialState: const CreateRestaurantState(),
  decide: (command, state) async* {
    if (state.exists) {
      throw RestaurantAlreadyExistsError(command.restaurantId);
    }
    yield RestaurantCreatedEvent(
      restaurantId: command.restaurantId,
      name: command.name,
      menu: command.menu,
    );
  },
  evolve: (state, event) {
    return switch (event) {
      RestaurantCreatedEvent(:final restaurantId) =>
        CreateRestaurantState(restaurantId: restaurantId),
      _ => state,
    };
  },
);
```

For cross-boundary consistency checks, use a wider event type and fold only the
events required by the slice. A `place_order` style decider can read restaurant
events and order events while producing only an order event.

### Repository Adapter

Use fmodel infrastructure interfaces as ports. Slice repositories are adapters
that translate a command into the exact event-store queries the decider needs:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import '../../platform/event_store/event_store.dart';
import 'command.dart';

final class CreateRestaurantEventRepository
    with EventRepositoryDefaults<CreateRestaurantCommand, RestaurantEvent>
    implements
        EventRepository<
          CreateRestaurantCommand,
          RestaurantEvent,
          NoMetadata,
          NoMetadata
        > {
  CreateRestaurantEventRepository(this._store);

  final EventStore _store;

  @override
  Stream<RestaurantEvent> fetchEvents(CreateRestaurantCommand command) {
    return _store
        .streamFor(
          tag: 'restaurantId',
          value: command.restaurantId.value,
          eventTypes: [RestaurantCreatedEvent],
        )
        .cast<RestaurantEvent>();
  }

  @override
  Stream<RestaurantEvent> save(Stream<RestaurantEvent> events) {
    return _store.append(events).cast<RestaurantEvent>();
  }
}
```

Keep this adapter inside the slice because its event queries are part of the
use-case boundary.

### Aggregate And Service

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import 'command.dart';
import 'decider.dart';
import 'repository.dart';
import 'state.dart';

typedef CreateRestaurantAggregate = EventSourcingAggregate<
  CreateRestaurantCommand,
  CreateRestaurantState,
  RestaurantEvent,
  NoMetadata,
  NoMetadata
>;

CreateRestaurantAggregate buildCreateRestaurantAggregate({
  required CreateRestaurantEventRepository repository,
}) {
  return createEventSourcingAggregate(
    decider: createRestaurantDecider,
    eventRepository: repository,
  );
}
```

```dart
import '../../platform/event_store/event_store.dart';
import 'aggregate.dart';
import 'repository.dart';

final class CreateRestaurantService {
  CreateRestaurantService({required EventStore eventStore}) {
    repository = CreateRestaurantEventRepository(eventStore);
    aggregate = buildCreateRestaurantAggregate(repository: repository);
  }

  late final CreateRestaurantEventRepository repository;
  late final CreateRestaurantAggregate aggregate;
}
```

### Handlers, DTOs, Serialization, Module

- `dto.dart` parses external JSON or UI input into the slice command.
- `handler.dart` catches slice-local domain errors and returns boundary results.
- `serialization.dart` registers codecs for events emitted by this slice.
- `module.dart` registers API/UI/serialization contributions with composition.

Follow existing project registries if present. For a new project, generate a
small `VerticalSlice` contract in `composition/vertical_slice.dart` and let each
module expose one slice descriptor.

## 5. State View Slices

Generate one state-view slice for each projection/read model:

```text
lib/state_view/restaurant_view/
  query.dart
  state.dart
  view.dart
  repository.dart
  service.dart
  handler.dart
  dto.dart
  module.dart
```

Default to an ephemeral view that folds events on demand. Generate a
materialized view only when the user asks for persisted read-model state or the
existing project already uses materialized views.

### View

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import 'state.dart';

final restaurantView = View<RestaurantViewState?, RestaurantEvent>(
  initialState: null,
  evolve: (state, event) {
    return switch (event) {
      RestaurantCreatedEvent(:final restaurantId, :final name, :final menu) =>
        RestaurantViewState(
          restaurantId: restaurantId,
          name: name,
          menu: menu,
        ),
      RestaurantMenuChangedEvent(:final menu) => state == null
          ? null
          : state.copyWith(menu: menu),
    };
  },
);
```

### Repository And Service

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import '../../platform/event_store/event_store.dart';

typedef RestaurantViewQuery = RestaurantId;

final class RestaurantEphemeralViewRepository
    implements EphemeralViewRepository<RestaurantEvent, RestaurantViewQuery> {
  RestaurantEphemeralViewRepository(this._store);

  final EventStore _store;

  @override
  Stream<RestaurantEvent> fetchEvents(RestaurantViewQuery query) {
    return _store.streamForQueries([
      (
        tag: 'restaurantId',
        value: query.value,
        eventType: RestaurantCreatedEvent,
      ),
      (
        tag: 'restaurantId',
        value: query.value,
        eventType: RestaurantMenuChangedEvent,
      ),
    ]).cast<RestaurantEvent>();
  }
}
```

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import '../../platform/event_store/event_store.dart';
import 'repository.dart';
import 'state.dart';
import 'view.dart';

final class RestaurantViewService {
  RestaurantViewService({required EventStore eventStore})
      : repository = RestaurantEphemeralViewRepository(eventStore) {
    ephemeralView = createEphemeralView(
      view: restaurantView,
      ephemeralViewRepository: repository,
    );
  }

  final RestaurantEphemeralViewRepository repository;
  late final EphemeralView<RestaurantViewState?, RestaurantEvent, RestaurantId>
      ephemeralView;

  Future<RestaurantViewState?> query(RestaurantId restaurantId) {
    return ephemeralView.handle(restaurantId);
  }
}
```

Handlers and DTO encoders stay in the same `state_view/<read_model>/` slice.

## 6. Automation Slices

Generate an automation slice for each process policy that reacts to events and
emits commands or other actions:

```text
lib/automation/order_payment_policy/
  saga.dart
  publisher.dart
  service.dart
  handler.dart
  module.dart
```

Use `Saga<AR, A>` for event-to-action decisions:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/order/api.dart';
import '../../state_change/mark_order_as_prepared/command.dart';

final markPreparedWhenPaidSaga =
    saga<OrderEvent, MarkOrderAsPreparedCommand>((event) async* {
  switch (event) {
    case OrderPaidEvent(:final orderId):
      yield MarkOrderAsPreparedCommand(orderId: orderId);
    default:
      break;
  }
});
```

Use `createSagaManager` when the generated slice needs to publish emitted
commands through an injected action publisher:

```dart
import 'package:fmodel/fmodel.dart';

import 'saga.dart';

final class OrderPaymentPolicyService {
  OrderPaymentPolicyService({
    required ActionPublisher<MarkOrderAsPreparedCommand, NoMetadata, NoMetadata>
        actionPublisher,
  }) {
    sagaManager = createSagaManager(
      saga: markPreparedWhenPaidSaga,
      actionPublisher: actionPublisher,
    );
  }

  late final SagaManager<
    OrderEvent,
    MarkOrderAsPreparedCommand,
    NoMetadata,
    NoMetadata
  > sagaManager;
}
```

Automation slices may import state-change commands, but they do not own those
commands. Keep command execution in the target state-change slice.

## 7. Translation Slices

Generate translation slices for external boundaries: imported messages, public
API DTO variants, partner integrations, legacy event formats, or UI-specific
anti-corruption mapping.

```text
lib/translation/public_restaurant_api/
  dto.dart
  mapper.dart
  codec.dart
  port.dart
  adapter.dart
  handler.dart
  module.dart
```

Rules:

- `dto.dart` contains external shapes and parsing/encoding helpers.
- `mapper.dart` converts external DTOs to commands, events, queries, or view
  DTOs.
- `port.dart` defines external service contracts when the domain must call out.
- `adapter.dart` implements a port with a concrete client or platform service.
- Translation slices must not contain business decisions that belong in
  deciders, views, or sagas.
- Domain events and value objects stay in `bounded_contexts/<name>/`.

## 8. Platform And Composition

Use fmodel interfaces as ports and keep generic adapters outside slices.

For a new runnable demo, generate a small event-store port under
`lib/platform/event_store/`:

```dart
abstract interface class EventStore {
  Stream<Object> append(Stream<Object> events);

  Stream<Object> streamFor({
    required String tag,
    required String value,
    required List<Type> eventTypes,
  });

  Stream<Object> streamForQueries(
    List<({String tag, String value, Type eventType})> queries,
  );
}
```

Generate an in-memory adapter by default. Add SQLite or another persistent
adapter only when requested or when the target project already has one.

Composition should be the only place that wires all slices:

```dart
abstract interface class VerticalSlice {
  String get name;

  void registerApi(ApiRegistry registry, AppContext context);

  void registerSerialization(SerializationRegistry registry);
}
```

Each generated `module.dart` registers only its own routes, codecs, and optional
UI contributions. `composition/slice_registry.dart` imports module files and
lists all slices.

## 9. Tests

Mirror the top-level source categories under `test/`:

```text
test/
  bounded_contexts/
    restaurant/api_test.dart
  state_change/
    create_restaurant/
      decider_test.dart
      repository_test.dart
      handler_test.dart
  state_view/
    restaurant_view/
      view_test.dart
      repository_test.dart
      service_test.dart
  automation/
    order_payment_policy/
      saga_test.dart
      service_test.dart
  translation/
    public_restaurant_api/
      mapper_test.dart
      codec_test.dart
```

Use `package:test`. Generate small reusable GWT helpers under `test/platform`
or `test/support` when there are several slices.

Decider tests should fold given events into state, execute the command, and
compare emitted events:

```dart
test('CreateRestaurant - success', () async {
  await createRestaurantDecider
      .givenEvents(const <RestaurantEvent>[])
      .whenCommand(command)
      .thenEvents([restaurantCreated]);
});
```

Repository tests should use the generated in-memory event store and verify that
the slice repository loads exactly the events needed for its decision.

View tests should use Given/Then event folding:

```dart
test('RestaurantView - menu changed after creation', () {
  restaurantView
      .givenEvents([restaurantCreated, restaurantMenuChanged])
      .thenState(expectedRestaurantView);
});
```

Automation tests should assert emitted commands from saga reactions. Translation
tests should assert DTO parsing, mapping, and codec round trips.

## 10. Workflow

1. Parse the user's Event Model diagram into a table, formulas, and Mermaid
   diagram.
2. Identify bounded contexts from domain vocabulary and event ownership.
3. Generate bounded-context contracts first.
4. Generate state-change slices from command -> event formulas.
5. Generate state-view slices from projection <- event formulas.
6. Generate automation slices from event-to-command policies or process notes.
7. Generate translation slices for external boundaries only when present in the
   model or requested by the user.
8. Generate or update platform ports/adapters and composition registries.
9. Generate mirrored tests.
10. Run `dart format .`, `dart analyze`, and `dart test` in the generated Dart
    package when a package exists.

Preserve existing project conventions when adding to an existing package, but do
not collapse the four top-level slice folders back under bounded contexts.
