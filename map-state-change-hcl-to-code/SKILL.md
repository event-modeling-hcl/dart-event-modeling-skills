---
name: map-state-change-hcl-to-code
description: >
  Generates one Dart state-change slice in lib/slices/ with fmodel-dart from a
  state_change workflow, or the command code of an automation workflow, in an
  Event Modeling HCL v0.8.0 (.em.hcl) model. The slice holds the command,
  state, errors, decider, event repository, aggregate, service, handler,
  module, and tests. Use when the user wants Dart code for a state_change
  workflow, a command, a lifecycle rule, or a decider from a .em.hcl model, or
  adds a state_change workflow to a package that map-event-model-hcl-to-code
  generated.
license: Apache 2.0
metadata:
  author: fraktalio
  version: '2.0.0'
  pattern: event-sourcing-command-slice
  input-language: Event Modeling HCL v0.8.0
  target-library: fmodel-dart
  example-repo: https://github.com/dclimber/fmodel_dart
  compatibility: Dart SDK ^3.10.0, package:fmodel/fmodel.dart, package:test
  requires-skill: map-event-model-hcl-to-code
---

# Map an HCL State Change to a Dart Slice

This skill generates one state-change slice from one `state_change` workflow.
A state-change slice is the folder `lib/slices/<workflow>/`. It holds all code
that turns a command into events. A command is a request to change the system.
A decider is the fmodel-dart component that selects the events for a command
from the current state.

## Before you start

This skill uses the reading rules and the shared code of the
`map-event-model-hcl-to-code` skill. Make sure that these conditions are true:

1. You have the generation inventory of the model. The
   `references/HCL-TO-MODEL.md` file of `map-event-model-hcl-to-code` tells
   you how to build it.
2. `lib/bounded_contexts/<context>/api.dart` exists for each bounded context
   that the workflow uses. It contains each event that the workflow emits or
   reads, and the lifecycle state enum when a lifecycle names the aggregate.
3. `lib/platform/event_store/event_store.dart` exists.

If a condition is false, use the `map-event-model-hcl-to-code` skill first.
Then come back to this skill.

## Read the workflow

A `state_change` workflow has this flow:

```text
screen or external trigger -> command -> event
```

Read these HCL values:

| HCL value | Use in the slice |
| --------- | ---------------- |
| `command` fields | The fields of the command class |
| `command.to` | The bounded-context events that the decider emits |
| `command.aggregate` and the `identity` of the aggregate | The event stream that the repository loads |
| `aggregate_dependencies` | Other event streams that the repository loads for the decision |
| `transition` and `invalid_transition` blocks that name the command | The lifecycle rules of the decider |
| `field_source` blocks | The mapping from screen fields to command fields, and from command fields to event fields |
| `screen.to`, screen `kind`, `api_endpoint`, `actor` | The DTO, the handler, the UI, and the module |
| `external_trigger` | The handler input when no screen flows to the command |
| `scenario` blocks | The tests |

A command has an incoming flow from a screen, or `external_trigger = true`.
`api_endpoint` on the command gives the route of the handler. An API screen
(`kind = "api"`) gives an API route in `handler.dart`. A UI screen (no `kind`,
or `kind = "ui"`) gives UI code in `ui/`.

Generate one slice for each workflow. Split a workflow into more slices only
when it holds commands that are independent and do not share one use case.
The folder name is the workflow label. If two slices get the same folder name,
use the collision rule of `map-event-model-hcl-to-code`.

Do not add relationships that the resolved HCL references do not contain.

## Command of an automation

The `map-automation-hcl-to-code` skill also uses this skill. It sends each
command that an `automation` workflow declares here. For that command:

- The target folder is `lib/slices/<automation>/<command>/`, a subfolder of the
  automation slice. Each relative import gets one more `../`.
- The incoming flow is the processor of the automation. The automation slice
  sends the command to the service of this subfolder.
- Generate `command.dart`, `state.dart`, `errors.dart`, `decider.dart`,
  `repository.dart`, `aggregate.dart`, and `service.dart`. Generate no DTO,
  handler, UI, or module. The automation slice owns the boundary.
- The tests of the decider come from the action form scenarios of the
  automation whose `when` step is this command, and from the `then` event steps
  that follow a dispatch of this command.

## Slice files

Generate only the files that the model or the user request needs:

| File | Content |
| ---- | ------- |
| `command.dart` | The command class with value equality |
| `state.dart` | The decider state. It holds only the facts that the decision needs. |
| `errors.dart` | The slice-local domain errors |
| `decider.dart` | The `Decider<C, S, E>` with `decide` and `evolve` |
| `repository.dart` | The `EventRepository` adapter that loads the events that the decider needs |
| `aggregate.dart` | The `EventSourcingAggregate` type and its builder |
| `service.dart` | Builds the repository and the aggregate from the `EventStore` port |
| `dto.dart` | Parses API or UI input into the command |
| `handler.dart` | Catches slice-local domain errors and returns boundary results. Holds the API route of an API screen. |
| `serialization.dart` | Registers codecs for the events that this slice emits |
| `module.dart` | Registers the routes, codecs, and UI parts of the slice with composition |
| `ui/` | UI code for each UI screen of the workflow |

## Workflow

Copy this checklist and update it while you work:

```text
State-change slice progress:
- [ ] Step 1: Make sure that the conditions in "Before you start" are true
- [ ] Step 2: Generate the command, the state, and the errors
- [ ] Step 3: Generate the decider
- [ ] Step 4: Generate the repository, the aggregate, and the service
- [ ] Step 5: Generate the DTO, the handler, the serialization, and the module
- [ ] Step 6: Generate the tests and the property laws
- [ ] Step 7: Format, analyze, and test
```

Steps 2 to 5: Read [references/CODE.md](references/CODE.md). It gives the
code shape for each file. Follow these rules:

- The decider emits only the events in `command.to`.
- Map the fields with the `field_source` blocks of the workflow. Section 5 of
  `references/HCL-TO-MODEL.md` of `map-event-model-hcl-to-code` gives the rules
  for fields without a source.
- If a lifecycle has a transition or an invalid transition for the command,
  the decider state holds the lifecycle state. The decider rejects the command
  in each `before` state of an invalid transition, with the `reason` as the
  error message.
- If the decision needs events from another bounded context, use a wider event
  type in the decider. Fold only the events that the slice needs. To fold is to
  apply the events one by one to the state.
- Keep errors in the slice, unless the same error is part of a stable
  cross-slice domain contract.
- Keep the repository adapter in the slice. Its event queries are part of the
  use case.

Step 6: Read [references/TESTS.md](references/TESTS.md) and the shared rules in
the `references/TEST-RULES.md` file of `map-event-model-hcl-to-code`. Map the
scenarios of the workflow with this table:

| Given | When | Then | Generated tests |
| ----- | ---- | ---- | --------------- |
| zero or more events | exactly one command | one or more events or errors | Decider, repository, and handler tests |

Step 7: Run `dart format .`, `dart analyze`, and `dart test`. If a command
reports a problem, fix the generated code and run the command again. If
`map-event-model-hcl-to-code` runs a whole-model generation, it does this step
once at the end.
