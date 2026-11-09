# Test Rules for All Generated Code

This reference gives the test rules that bounded contexts and all slices use.
Each slice skill adds the tests and property laws for its slice kind.

## Contents

1. Test folders
2. Test names
3. Property laws
4. Value equality
5. Codec round trip
6. Bounded-context tests

## 1. Test Folders

Mirror the source folders under `test/`:

```text
test/
  bounded_contexts/
    restaurant/api_test.dart
  slices/
    <slice>/
      <command>/        (only in an automation slice)
      <readmodel>/      (only in an automation slice)
  support/
```

Use `package:test`. If the package has more than one slice, put small reusable
Given/When/Then helpers in `test/support/`. Name each generator helper after
the type that it makes, for example `sampleRestaurantEvents`. If more than one
slice uses a helper, put it in `test/support/`.

## 2. Test Names

Each scenario gives at least one test. Use the scenario `title` as the test
name when it exists. Otherwise use the scenario label. If scenarios have a
`case`, put the tests of one case in one `group`, named after the case, for
example `group('state_violation', ...)`. Keep the written order of the
scenarios in each group. The `case` names the kind of the rule. It never
changes what the test checks.

## 3. Property Laws

A property law is a rule that is true for all inputs of a given kind. Each
generated test suite states property laws in addition to the example tests
from the scenarios.

Write each law as a `package:test` test over generated or listed inputs. Do not
add a package dependency for this. A small hand-written generator loop is
sufficient. Make the inputs from scenario fixtures, field `example` values, and
small changes to them.

Put a Design-by-Contract comment above each law test. Use `// @requires` for
the precondition. Use `// @ensures` for the law.

## 4. Value Equality

The laws compare values with `==`. Thus, every value type that a law compares
must have value equality. This includes events, commands, nested value objects
such as `RestaurantMenu`, and read-model states such as `RestaurantViewState`.
Each such class must override `operator ==` and `hashCode`, or the type must be
a Dart record.

If `package:collection` is already a dependency, compare a list in a value with
`ListEquality`. If it is not a dependency, compare the elements with a
hand-written loop:

```dart
final class RestaurantMenu {
  const RestaurantMenu({required this.items});

  final List<MenuItem> items;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RestaurantMenu) return false;
    if (items.length != other.items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);
}
```

## 5. Codec Round Trip

Apply this law to every event codec and every command codec:

```dart
// @ensures decode(encode(e)) == e
test('RestaurantEvent codec - round trip', () {
  for (final event in sampleRestaurantEvents()) {
    expect(decodeRestaurantEvent(encodeRestaurantEvent(event)), event);
  }
});
```

## 6. Bounded-Context Tests

For each bounded context, generate `test/bounded_contexts/<name>/api_test.dart`.
It holds the codec round-trip law for the shared event codecs of the context.
Make the sample events from the field `example` values of the HCL model.
