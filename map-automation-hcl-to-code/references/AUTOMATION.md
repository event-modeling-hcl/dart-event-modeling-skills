# Automation Slice Code

This reference gives the code shape for an automation slice. An automation
slice reacts to internal events and sends commands. A translation slice uses
the processor rules of this reference, too. The examples use an
`order_payment_policy` automation that declares the command
`mark_order_as_prepared` and sends it when an order is paid.

```text
lib/slices/order_payment_policy/
  saga.dart
  publisher.dart
  service.dart
  handler.dart
  module.dart
  mark_order_as_prepared/
    command.dart
    state.dart
    errors.dart
    decider.dart
    repository.dart
    aggregate.dart
    service.dart
```

## Contents

1. Saga
2. Saga over a read model
3. Processor with history
4. Saga manager and service
5. Other files

## 1. Saga

Use `Saga<AR, A>` for the decision from event to command. Use `processor.from`
or `readmodel.from` to find the events that the saga consumes. Use
`processor.to` to find the commands that the saga sends. The command fields
take their values from the fields that the `field_source` blocks name. Import
each command class from its subfolder:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/order/api.dart';
import 'mark_order_as_prepared/command.dart';

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

A saga is stateless. If a dispatch depends on more than the consumed event,
use section 2 or section 3.

## 2. Saga over a Read Model

If the processor reads a read model of the automation (`readmodel.to`), for
example a to-do list, the saga reacts to the read-model state. It sends one
command for each item that needs it. The read-model subfolder holds the View
that builds the list:

```dart
import 'package:fmodel/fmodel.dart';

import 'appointments_needing_reminder/state.dart';
import 'request_reminder/command.dart';

final reminderProcessorSaga = saga<
  AppointmentsNeedingReminderState,
  RequestReminderCommand
>((todo) async* {
  for (final item in todo.items) {
    yield RequestReminderCommand(appointmentId: item.appointmentId);
  }
});
```

The handler loads the read-model state with the service of the read-model
subfolder, then passes it to the saga manager.

## 3. Processor with History

The processor needs history when an action form scenario with a processor
`when` step has a `given` event that the processor does not consume, or when a
consumed event field has `deduplication_key = true`. For example:

```hcl
scenario "repeated_payment_is_ignored" {
  case = "business_duplicate"
  given { event = event.booking.deposit_recorded }
  given { event = event.payments.payment_received }
  when  { processor = processor.deposit_translator }
  then {
    expect_no_dispatch = true
    command            = command.record_deposit
  }
}
```

Generate `processor_state.dart` with a `View<S, E>` that folds these history
events into the facts that the dispatch needs. For a deduplication key, the
state holds the key values that the internal events already recorded. The
saga reacts to a record of the state and the consumed event:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/booking/api.dart';
import '../../bounded_contexts/payments/api.dart';
import 'processor_state.dart';
import 'record_deposit/command.dart';

typedef DepositTranslatorInput = ({
  DepositTranslatorState state,
  PaymentReceivedEvent event,
  BookingId bookingId,
});

final depositTranslatorSaga =
    saga<DepositTranslatorInput, RecordDepositCommand>((input) async* {
  final reference = PaymentReference(input.event.paymentReference);
  if (input.state.recordedReferences.contains(reference)) return;
  yield RecordDepositCommand(
    bookingId: input.bookingId,
    paymentReference: reference,
    amount: Amount(input.event.paidAmount),
  );
});
```

This processor belongs to a translation. `bookingId` is the internal identity
that the handler resolves from the correlation key of the external event.
`references/TRANSLATION.md` gives the rule.

The handler loads the history events from the event store, folds them with the
View, and passes the record to the saga manager. Use the deduplication key or
the correlation key as the tag of the history query.

## 4. Saga Manager and Service

If the slice must publish the sent commands, use `createSagaManager` with an
injected action publisher:

```dart
import 'package:fmodel/fmodel.dart';

import '../../bounded_contexts/order/api.dart';
import 'mark_order_as_prepared/command.dart';
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

## 5. Other Files

These files connect the slice to the rest of the package:

- `publisher.dart` implements the `ActionPublisher` port. It sends each
  command to the service of its command subfolder, which runs the decider.
- `handler.dart` receives the consumed events, loads the read-model state or
  the processor history when the processor needs it, and passes the input to
  the saga manager.
- `module.dart` registers the slice with composition, including the codecs
  and routes of its subfolders.

The saga only selects the commands. The decider in the command subfolder
executes each command and emits its events.
