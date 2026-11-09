# State-View Slice Tests

This reference gives the tests and the property laws for a state-view slice.
Follow also the shared test rules of `map-event-model-hcl-to-code`.

## Test files

```text
test/slices/restaurant_view/
  view_test.dart
  repository_test.dart
  service_test.dart
```

Repository tests use the generated in-memory event store. They make sure that
the repository loads the events in `readmodel.from` for the query, and no
other events.

## Scenario tests

Each scenario gives one view test. The `given` events fold into the state. The
test compares the result with the `then` read model:

```dart
test('RestaurantView - menu changed after creation', () {
  restaurantView
      .givenEvents([restaurantCreated, restaurantMenuChanged])
      .thenState(expectedRestaurantView);
});
```

Use `readmodel.question` in the test names. Name and group the tests with the
shared test rules, for example by the scenario `case` (`appear`, `change`,
`disappear`). If a `then` step has an `error` target, generate a test that
expects the named rejection.

A scenario with `empty_history = true` has no `given` step. Its test checks the
initial state of the View:

```dart
test('OpenBookings - no booking yet', () {
  openBookingsView.givenEvents(const []).thenState(const OpenBookingsState());
});
```

A `then` step with `expect_empty_list = true` expects a read model with no
items. Fields on a `then` step give the expected values of the read model.

## Property laws

Apply these laws to every View:

```dart
// @requires given is the scenario event list
// @ensures fold(initialState, given) == then
test('RestaurantView - fold of given events yields then read model', () {
  final state = given.fold(restaurantView.initialState, restaurantView.evolve);
  expect(state, expectedRestaurantView);
});

// @requires event is not consumed by the view
// @ensures evolve(s, event) == s
test('RestaurantView - ignores events it does not consume', () {
  for (final state in sampleRestaurantViewStates()) {
    for (final event in sampleUnconsumedEvents()) {
      expect(restaurantView.evolve(state, event), state);
    }
  }
});
```

The second law compiles only when the View accepts a wider event type, such as
the shared event supertype. If the View accepts only the events that it
consumes, do not generate the second law. Add a comment that gives the reason.
