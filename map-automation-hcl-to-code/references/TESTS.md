# Automation and Translation Slice Tests

This reference gives the tests for automation slices and translation slices.
Follow also the shared test rules of `map-event-model-hcl-to-code`.

## Test files

```text
test/slices/<workflow>/
  saga_test.dart
  service_test.dart
  mapper_test.dart          (translation slice only)
  codec_test.dart           (translation slice only)
  <command>/
    decider_test.dart
    repository_test.dart
  <readmodel>/
    view_test.dart
    repository_test.dart
```

## Action form scenarios

An automation scenario with one `when` step is an action form scenario. Map
each step with these rules:

- A `given` event that the processor consumes is the input of the saga.
- A `given` event that the processor does not consume is history. It folds into
  the processor state.
- A `given` read model is a read-model state fixture that the saga reads.
- A `when` processor is the saga reaction under test.
- A `when` command is a decider test in the command subfolder. The `given`
  events fold into the decider state.
- A `then` command is a dispatch assertion. The saga sends this command. Fields
  on the step give the expected command values.
- A `then` command with `expect_no_dispatch = true` asserts that the saga does
  not send any command of this type.
- A `then` event is an event that the decider in the command subfolder emits
  for the sent command.
- A `then { error = "..." }` step expects the named rejection and no emitted
  events.

Automation tests assert the commands that the saga sends:

```dart
test('OrderPaymentPolicy - paid order is marked as prepared', () async {
  final commands = await markPreparedWhenPaidSaga.react(orderPaid).toList();
  expect(commands, [MarkOrderAsPreparedCommand(orderId: orderId)]);
});
```

A no-dispatch assertion:

```dart
// @requires state.recordedReferences contains the payment reference
// @ensures react(input) sends no RecordDepositCommand
test('RecordDeposit - repeated payment is ignored', () async {
  final commands = await depositTranslatorSaga.react(input).toList();
  expect(commands.whereType<RecordDepositCommand>(), isEmpty);
});
```

If the `when` step is a processor and the scenario has `then` event steps, run
each sent command through its decider. The `given` events of the aggregate
fold into the decider state. Compare the emitted events with the `then`
events.

## View form scenarios

An automation scenario without a `when` step is a view form scenario. It
states the content of a read model of the automation, for example a to-do
list. Generate a View test in `test/slices/<workflow>/<readmodel>/` with the
rules of `map-state-view-hcl-to-code`: the `given` events fold into the state,
`empty_history = true` checks the initial state, and `expect_empty_list = true`
expects a list with no items.

## Translation tests

Translation tests assert DTO parsing, mapping, and codec round trips. If the
slice has a lookup port for a correlation key, test the handler with the
in-memory adapter: a known value sends the command, and an unknown value sends
no command.

## Property laws

Apply the codec round-trip law of the shared test rules to every codec of a
translation slice. The command classes need value equality, because the tests
compare commands with `==`. The deciders and Views in the subfolders get the
property laws of their slice skills.
