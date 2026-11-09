# State-Change Slice Code

This reference gives the code shape for each file of a state-change slice. The
examples use the `create_restaurant` workflow of a `restaurant` bounded
context.

## Contents

1. Command, state, and errors
2. Decider
3. Lifecycle rules
4. Repository adapter
5. Aggregate and service
6. DTO, handler, serialization, and module

```text
lib/slices/create_restaurant/
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

## 1. Command, State, and Errors

Generate the command from the workflow `command` block. Its fields come from
the declared HCL fields.

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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreateRestaurantCommand &&
            restaurantId == other.restaurantId &&
            name == other.name &&
            menu == other.menu;
  }

  @override
  int get hashCode => Object.hash(restaurantId, name, menu);
}
```

```dart
// state.dart
import '../../bounded_contexts/restaurant/api.dart';

final class CreateRestaurantState {
  const CreateRestaurantState({this.restaurantId});

  final RestaurantId? restaurantId;

  bool get exists => restaurantId != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreateRestaurantState && restaurantId == other.restaurantId;
  }

  @override
  int get hashCode => restaurantId.hashCode;
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

## 2. Decider

The `decide` function emits the events in `command.to`, or it throws a
slice-local error. The `evolve` function folds events into the state. The
event fields take their values from the command fields that the
`field_source` blocks name.

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

If the decision needs facts from more than one bounded context, use a wider
event type. Fold only the events that the slice needs. For example, a
`place_order` decider can read restaurant events and order events, and emit
only an order event.

## 3. Lifecycle Rules

Use this section when a `lifecycle` has a `transition` or an
`invalid_transition` whose `command` is the command of the slice. The example
uses the `booking` lifecycle and the `confirm_booking` command:

```hcl
transition "confirm_booking" {
  command = command.confirm_booking.confirm_booking
  events  = [event.booking.booking_confirmed]
  before  = [state.open]
  after   = state.confirmed
}

invalid_transition "confirm_canceled_booking" {
  command = command.confirm_booking.confirm_booking
  reason  = "A canceled booking cannot be confirmed."
  before  = [state.canceled]
}
```

The decider state holds the lifecycle state enum of the bounded context. A
`null` value means that the stream has not started. `evolve` maps each event
of each transition of the lifecycle to the `after` state of that transition.
The repository loads these events from the stream of the aggregate identity:

```dart
// state.dart
import '../../bounded_contexts/booking/api.dart';

final class ConfirmBookingState {
  const ConfirmBookingState({this.lifecycle});

  final BookingLifecycleState? lifecycle;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ConfirmBookingState && lifecycle == other.lifecycle;
  }

  @override
  int get hashCode => lifecycle.hashCode;
}
```

```dart
// errors.dart
final class ConfirmCanceledBookingError extends DomainError {
  const ConfirmCanceledBookingError()
    : super('A canceled booking cannot be confirmed.');
}
```

```dart
// decider.dart
final confirmBookingDecider =
    Decider<ConfirmBookingCommand, ConfirmBookingState, BookingEvent>(
  initialState: const ConfirmBookingState(),
  decide: (command, state) async* {
    if (state.lifecycle == BookingLifecycleState.canceled) {
      throw const ConfirmCanceledBookingError();
    }
    yield BookingConfirmedEvent(bookingId: command.bookingId);
  },
  evolve: (state, event) {
    return switch (event) {
      BookingOpenedEvent() =>
        const ConfirmBookingState(lifecycle: BookingLifecycleState.open),
      BookingConfirmedEvent() =>
        const ConfirmBookingState(lifecycle: BookingLifecycleState.confirmed),
      BookingCanceledEvent() =>
        const ConfirmBookingState(lifecycle: BookingLifecycleState.canceled),
      _ => state,
    };
  },
);
```

Name each error class after its invalid transition. Use the `reason` as the
message, as written. Generate one check for each invalid transition, and no
check that the lifecycle does not state. In this example, the lifecycle states
no rule for `confirm_booking` in the `confirmed` state. The decider accepts
the command there, and the report to the user names the gap.

If the transitions of the command all have `before = []`, the command starts
a stream. Reject it on an existing stream only when an invalid transition or a
scenario states that rule.

## 4. Repository Adapter

The slice repository is an adapter for the fmodel `EventRepository` port. It
converts a command into the exact event store queries that the decider needs.
Use `command.aggregate` and `aggregate_dependencies` to select the streams.
The tag of a stream is the `identity` field of the aggregate. Without an
`identity`, use the `id_attribute` field.

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

## 5. Aggregate and Service

The aggregate joins the decider and the repository. The service builds both
from the `EventStore` port.

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

## 6. DTO, Handler, Serialization, and Module

These files connect the slice to the outside:

- `dto.dart` parses the input of the screen into the slice command. The
  command fields take their values from the screen fields that the
  `field_source` blocks name.
- `handler.dart` catches slice-local domain errors and returns boundary
  results. For an API screen (`kind = "api"`), it holds the route that the
  `api_endpoint` of the screen names, for example `POST /pets`. If the screen
  has no `api_endpoint`, use the `api_endpoint` of the command. For
  `external_trigger = true`, the handler is the entry point that the trigger
  calls.
- `ui/` holds the UI code for each UI screen (no `kind`, or `kind = "ui"`).
- `serialization.dart` registers codecs for the events that this slice emits.
- `module.dart` registers the API, UI, and serialization parts with
  composition.

If the project has registries, use them. For a new project, each module
exposes one `VerticalSlice` descriptor. The `references/SHARED-CODE.md` file of
`map-event-model-hcl-to-code` gives the `VerticalSlice` contract.
