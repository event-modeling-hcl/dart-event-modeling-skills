# State-Change Slice Tests

This reference gives the tests and the property laws for a state-change slice.
Follow also the shared test rules in the `references/TEST-RULES.md` file of
`map-event-model-hcl-to-code`. Those rules cover value equality, the
Design-by-Contract comments, and the generator helpers.

## Contents

1. Test files
2. Scenario tests
3. Property laws
4. Error scenarios
5. Lifecycle tests

## 1. Test Files

```text
test/slices/create_restaurant/
  decider_test.dart
  repository_test.dart
  handler_test.dart
```

For the command of an automation, the tests go in
`test/slices/<automation>/<command>/`. That folder has no handler test.

## 2. Scenario Tests

Each scenario gives one decider test. The `given` events fold into the state.
The `when` command runs. The test compares the emitted events with the `then`
events. Name and group the tests with the shared test rules, for example by
the scenario `case`:

```dart
test('CreateRestaurant - success', () async {
  await createRestaurantDecider
      .givenEvents(const <RestaurantEvent>[])
      .whenCommand(command)
      .thenEvents([restaurantCreated]);
});
```

Repository tests use the generated in-memory event store. They make sure that
the slice repository loads exactly the events that the decision needs.

## 3. Property Laws

Apply these laws to every decider. The `given`, `command`, and `then` values
come from each scenario:

```dart
// @requires state == fold(initialState, given)
// @ensures decide(command, state) emits then
test('CreateRestaurant - decide after fold yields then events', () async {
  final state = given.fold(
    createRestaurantDecider.initialState,
    createRestaurantDecider.evolve,
  );
  final first = await createRestaurantDecider.decide(command, state).toList();
  final second = await createRestaurantDecider.decide(command, state).toList();
  expect(first, then);
  expect(second, first);
});

// @ensures fold(s0, a ++ b) == fold(fold(s0, a), b)
test('CreateRestaurant - fold preserves order', () {
  final decider = createRestaurantDecider;
  for (final (a, b) in sampleEventSplits()) {
    final whole = [...a, ...b].fold(decider.initialState, decider.evolve);
    final stepwise = b.fold(
      a.fold(decider.initialState, decider.evolve),
      decider.evolve,
    );
    expect(stepwise, whole);
  }
});
```

If the slice has a command codec, apply the codec round-trip law of the shared
test rules to it.

## 4. Error Scenarios

Map each `then { error = "..." }` step to a test. The test makes sure that the
decider rejects the command and emits no events:

```dart
// @requires state == fold(initialState, given)
// @ensures decide(command, state) throws RestaurantAlreadyExistsError
// @ensures decide(command, state) emits no events
test('CreateRestaurant - rejects an existing restaurant', () async {
  final state = given.fold(
    createRestaurantDecider.initialState,
    createRestaurantDecider.evolve,
  );
  final emitted = <RestaurantEvent>[];
  await expectLater(
    createRestaurantDecider.decide(command, state).forEach(emitted.add),
    throwsA(isA<RestaurantAlreadyExistsError>()),
  );
  expect(emitted, isEmpty);
});
```

## 5. Lifecycle Tests

If the decider has lifecycle rules, add one test for each `before` state of
each invalid transition of the command. Make the state with the transition
events that lead to it. The test expects the error with the `reason` message
and no emitted events. A scenario that already covers the same state, for
example a `state_violation` scenario, gives this test. Do not duplicate it.

```dart
// @requires fold(initialState, given).lifecycle == BookingLifecycleState.canceled
// @ensures decide(command, state) throws ConfirmCanceledBookingError
// @ensures decide(command, state) emits no events
```
