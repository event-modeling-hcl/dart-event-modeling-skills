# Shared Code: Package, Bounded Contexts, Platform, Composition

This reference gives the code that all slices use. Generate it before any
slice. Generated code uses `fmodel-dart` (`package:fmodel/fmodel.dart`) and
`package:test`.

## Contents

1. Package shape
2. Bounded contexts: `value_objects.dart`, `events.dart`, `event_tags.dart`,
   `lifecycles.dart`, `serialization.dart`, `api.dart`
3. Event store port
4. Composition

## 1. Package Shape

For a new package, create this structure. The slice skills fill the
`slices/` folder.

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
      lifecycles.dart
      serialization.dart
  slices/
    <slice>/
  composition/
    app_services.dart
    slice_registry.dart
    vertical_slice.dart
  platform/
    event_store/
    server/
test/
  bounded_contexts/
  slices/
    <slice>/
  support/
  platform/
```

All slices are direct children of `lib/slices/`, whatever their workflow kind.
Section 10 of [HCL-TO-MODEL.md](HCL-TO-MODEL.md) gives the slice folder names.
If the model has no slice and git must track the folder, add a `.gitkeep`
file. Create only the slice files that the model or the user request needs.

A slice file imports a bounded context with a relative import:
`../../bounded_contexts/<name>/api.dart`. A file in a subfolder of an
automation slice adds one `../`.

The `pubspec.yaml` file must contain at least these entries:

```yaml
environment:
  sdk: ^3.10.0

dependencies:
  fmodel: any

dev_dependencies:
  lints: ^6.0.0
  test: ^1.31.2
```

In an existing Dart package, keep its dependency versions, its platform
adapters, and its composition conventions.

## 2. Bounded Contexts

A bounded context is the part of the domain that owns one set of events and
value objects. Each bounded-context folder holds shared domain contracts only:

```text
lib/bounded_contexts/restaurant/
  api.dart
  value_objects.dart
  events.dart
  event_tags.dart
  lifecycles.dart
  serialization.dart
```

Do not put commands, deciders, handlers, services, UI, repositories, or
slice-local errors in bounded-context folders.

Generate value objects from the `field_type` declarations of the bounded
context. Generate events from its `event` declarations. Event fields come from
the declared HCL fields after you apply `fields = [...]`, `field` blocks,
`optional`, `cardinality`, and `subfield`. Every field has an explicit `type`.
Do not infer a type from a field name.

### `value_objects.dart`

Use extension types for simple scalar wrappers. Use immutable classes for
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

Every compound value needs value equality. A value that holds a list compares
the list elements. [TEST-RULES.md](TEST-RULES.md) gives the rule and an
example.

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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RestaurantCreatedEvent &&
            restaurantId == other.restaurantId &&
            name == other.name &&
            menu == other.menu &&
            isFinal == other.isFinal;
  }

  @override
  int get hashCode => Object.hash(restaurantId, name, menu, isFinal);
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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RestaurantMenuChangedEvent &&
            restaurantId == other.restaurantId &&
            menu == other.menu &&
            isFinal == other.isFinal;
  }

  @override
  int get hashCode => Object.hash(restaurantId, menu, isFinal);
}
```

If more than one bounded context uses the same event store, generate a small
shared event supertype in `lib/bounded_contexts/`. The event base class of each
bounded context implements this supertype. The supertype has no
infrastructure code.

### `event_tags.dart`

An event tag is a name and a value that the event store uses to find events.
Each event of an aggregate with an `identity` gets the tag of its identity
field. Other tags come from `id_attribute` fields. Generate tag extraction next
to the events:

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

If an event identifies more than one entity, return all tags of the event. The
event store can index all non-empty subsets of the tags.

### `lifecycles.dart`

Generate this file only when a `lifecycle` names an aggregate of the context.
Generate one enum for each lifecycle, with one value for each `state` block in
ID order. Several deciders use the enum, so it is a shared contract:

```dart
/// The states of a booking stream.
enum BookingLifecycleState { canceled, confirmed, open }
```

Put the `title` or the `description` of a state in a doc comment of its value.
Each decider maps the transition events to the `after` states in its own
`evolve`. The state-change skill gives the rules.

### `serialization.dart`

Put shared encode and decode functions for events in the bounded context when
they are stable domain contracts. If only one translation slice needs a codec,
put the codec in that slice.

### `api.dart`

Export the contract of the context:

```dart
library;

export 'value_objects.dart';
export 'events.dart';
export 'event_tags.dart';
export 'lifecycles.dart';
export 'serialization.dart';
```

Export `lifecycles.dart` only when the file exists.

## 3. Event Store Port

A port is an interface that slices use and that an adapter implements. Slices
use fmodel interfaces as ports. Generic adapters stay outside the slices.

For a new runnable package, generate this event store port in
`lib/platform/event_store/event_store.dart`:

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
adapter only when the user asks for it or the target project already has one.

## 4. Composition

Composition is the only place that wires all slices together. For a new
package, generate this contract in `lib/composition/vertical_slice.dart`:

```dart
abstract interface class VerticalSlice {
  String get name;

  void registerApi(ApiRegistry registry, AppContext context);

  void registerSerialization(SerializationRegistry registry);
}
```

Each slice has a `module.dart` file in `lib/slices/<slice>/` that exposes one
slice descriptor. The module registers only its own routes, codecs, and
optional UI parts. The subfolders of an automation slice have no module; the
module of the automation slice registers them. `composition/slice_registry.dart`
imports all module files and lists all slices in inventory order. If the
project already has registries, use them.
