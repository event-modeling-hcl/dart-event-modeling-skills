# State-View Slice Code

This reference gives the code shape for each file of a state-view slice. The
examples use a `restaurant_view` read model of a `restaurant` bounded context.

## Contents

1. View
2. Ephemeral repository and service
3. Materialized variant
4. DTO, handler, and module

```text
lib/slices/restaurant_view/
  query.dart
  state.dart
  view.dart
  repository.dart
  service.dart
  handler.dart
  dto.dart
  module.dart
```

## 1. View

The `evolve` function folds each event of `readmodel.from` into the state. The
read-model fields take their values from the event fields that the
`field_source` blocks name. The state type must have value equality, because
the tests compare states with `==`.

If the read model is a list, the initial state is an empty list, so that an
`empty_history` scenario and an `expect_empty_list` step compare with the
empty list.

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

## 2. Ephemeral Repository and Service

The repository is an adapter for the fmodel `EphemeralViewRepository` port. It
converts a query into the event store queries for the events in
`readmodel.from`.

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

## 3. Materialized Variant

Use this variant only when the user asks for a stored read-model state, or the
project already uses materialized views. Generate a `ViewStateRepository`
adapter in the slice and connect it with `createMaterializedView`:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/restaurant/api.dart';
import 'state.dart';
import 'view.dart';

final class RestaurantViewStateRepository
    with ViewStateRepositoryDefaults<RestaurantEvent, RestaurantViewState?>
    implements
        ViewStateRepository<RestaurantEvent, RestaurantViewState?, NoMetadata> {
  RestaurantViewStateRepository(this._states);

  final Map<String, RestaurantViewState?> _states;

  @override
  Future<RestaurantViewState?> fetchState(RestaurantEvent event) async {
    final key = switch (event) {
      RestaurantCreatedEvent(:final restaurantId) => restaurantId.value,
      RestaurantMenuChangedEvent(:final restaurantId) => restaurantId.value,
    };
    return _states[key];
  }

  @override
  Future<RestaurantViewState?> save(RestaurantViewState? state) async {
    if (state == null) return null;
    _states[state.restaurantId.value] = state;
    return state;
  }
}

MaterializedView<RestaurantViewState?, RestaurantEvent, NoMetadata>
buildRestaurantMaterializedView({
  required RestaurantViewStateRepository repository,
}) {
  return createMaterializedView(
    view: restaurantView,
    viewStateRepository: repository,
  );
}
```

## 4. DTO, Handler, and Module

These files connect the slice to the outside:

- `dto.dart` encodes the read-model state for the screen. The screen fields
  take their values from the read-model fields that the `field_source` blocks
  name.
- `handler.dart` receives the query and returns the encoded read model. For an
  API screen (`kind = "api"`), it holds the route that the `api_endpoint` of
  the screen names, for example `GET /pets`.
- `ui/` holds the UI code for each UI screen (no `kind`, or `kind = "ui"`).
- `module.dart` registers the routes and the UI parts with composition.

If the project has registries, use them. For a new project, each module
exposes one `VerticalSlice` descriptor. The `references/SHARED-CODE.md` file of
`map-event-model-hcl-to-code` gives the `VerticalSlice` contract.
