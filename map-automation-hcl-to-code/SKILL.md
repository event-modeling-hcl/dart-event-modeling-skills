---
name: map-automation-hcl-to-code
description: >
  Generates one Dart slice in lib/slices/ with fmodel-dart from an automation
  workflow of an Event Modeling HCL v0.8.0 (.em.hcl) model. An automation that
  consumes only internal events becomes a Saga slice. An automation that
  consumes an event of an external bounded context is a translation and
  becomes an anti-corruption slice. Both go to lib/slices/<workflow>/, with the
  code of their commands and read models in subfolders. Use when the user
  wants Dart code for an automation, a processor, a saga, a policy, a to-do
  list reaction, a translation, or an external integration from a .em.hcl
  model.
license: Apache 2.0
metadata:
  author: fraktalio
  version: '2.0.0'
  pattern: event-sourcing-saga-and-translation-slice
  input-language: Event Modeling HCL v0.8.0
  target-library: fmodel-dart
  example-repo: https://github.com/dclimber/fmodel_dart
  compatibility: Dart SDK ^3.10.0, package:fmodel/fmodel.dart, package:test
  requires-skill: map-event-model-hcl-to-code, map-state-change-hcl-to-code, map-state-view-hcl-to-code
---

# Map an HCL Automation to a Dart Slice

This skill generates one slice from one `automation` workflow. An automation is
a reaction of the system to events. It reads events, optionally through a read
model, and sends a command. In fmodel-dart, a `Saga<AR, A>` maps an action
result of type `AR` (an event, or a read-model state) to actions of type `A`
(commands).

An automation becomes one of two slice kinds. Both kinds use the same folder,
`lib/slices/<workflow>/`:

| Slice kind | When |
| ---------- | ---- |
| Automation slice | All consumed events come from internal bounded contexts |
| Translation slice | At least one consumed event comes from a bounded context with `external = true` |

## Before you start

This skill uses the reading rules and the shared code of the
`map-event-model-hcl-to-code` skill. Make sure that these conditions are true:

1. You have the generation inventory of the model. The
   `references/HCL-TO-MODEL.md` file of `map-event-model-hcl-to-code` tells
   you how to build it.
2. `lib/bounded_contexts/<context>/api.dart` exists for each bounded context
   that the workflow uses.
3. `lib/platform/event_store/event_store.dart` exists.

If a condition is false, use the `map-event-model-hcl-to-code` skill first.
Then come back to this skill.

## Read the workflow

An `automation` workflow has this flow:

```text
event -> readmodel or processor -> command -> event
```

Read these HCL values:

| HCL value | Use in the slice |
| --------- | ---------------- |
| `readmodel.from`, `processor.from` | The events that the slice consumes |
| `readmodel` blocks | A read model of the automation, for example a to-do list |
| `readmodel.to` | The processor that reads the read model |
| `processor.to` | The commands that the slice sends |
| `command` blocks and `command.to` | The commands that the slice declares, and the events that they produce |
| `field_source` blocks | The mapping from consumed events to processor fields, and from processor fields to command fields |
| `correlation_key`, `deduplication_key` on consumed event fields | The lookup of the internal identity, and the check for a repeated delivery |
| `scenario` blocks | The tests |

Do not add relationships that the resolved HCL references do not contain.

## Classify the automation

The HCL language has no `translation` keyword. Translation is a slice kind of
the generated code only. Apply this rule once to each `automation` workflow:

- If at least one consumed event belongs to a `bounded_context` with
  `external = true`, the workflow is a translation slice.
- If no consumed event belongs to an external bounded context, the workflow is
  an automation slice.

An automation consumes an event through a `readmodel.from` edge or a
`processor.from` edge. The typed IR of emhcl marks each edge from a catalog
event with the `external` value of the bounded context of that event. If the IR
is available, use those marks.

## Slice layout

The slice folder is `lib/slices/<workflow>/`. It holds the code of all
elements that the workflow declares:

```text
lib/slices/<workflow>/
  saga.dart                   the processor
  processor_state.dart        only when the processor needs history
  publisher.dart, service.dart, handler.dart, module.dart
  <command>/                  one subfolder for each declared command
  <readmodel>/                one subfolder for each declared read model
```

A translation slice adds its boundary files to this layout.
`references/TRANSLATION.md` names them.

For each `command` of the workflow, use the `map-state-change-hcl-to-code`
skill. Its section "Command of an automation" generates the command, the
decider, the repository, the aggregate, and the service in
`lib/slices/<workflow>/<command>/`. The processor sends the command, and the
decider in the subfolder executes it.

For each `readmodel` of the workflow, use the `map-state-view-hcl-to-code`
skill. It generates the query, the state, the View, the repository, and the
service in `lib/slices/<workflow>/<readmodel>/`.

The slice imports no other slice. Generate the subfolders before the
processor, because the processor imports the command classes and the
read-model state.

## Workflow

Copy this checklist and update it while you work:

```text
Automation slice progress:
- [ ] Step 1: Make sure that the conditions in "Before you start" are true
- [ ] Step 2: Classify the automation as an automation slice or a translation slice
- [ ] Step 3: Generate the command and read-model subfolders
- [ ] Step 4: Generate the processor and the boundary files
- [ ] Step 5: Generate the tests and the property laws
- [ ] Step 6: Format, analyze, and test
```

Step 4: For an automation slice, read
[references/AUTOMATION.md](references/AUTOMATION.md). For a translation slice,
read [references/TRANSLATION.md](references/TRANSLATION.md) and the processor
rules of `references/AUTOMATION.md`.

Step 5: Read [references/TESTS.md](references/TESTS.md) and the shared rules in
the `references/TEST-RULES.md` file of `map-event-model-hcl-to-code`. An
automation scenario without a `when` step is a view form scenario. Map the
scenarios of the workflow with this table:

| Form | Given | When | Then | Generated tests |
| ---- | ----- | ---- | ---- | --------------- |
| Action | zero or more events or read models | exactly one processor | events, errors, or commands | Saga or mapper tests, and decider tests for the `then` events |
| Action | zero or more events or read models | exactly one command | events or errors | Decider tests in the command subfolder |
| View | one or more events, or none with `empty_history = true` | none | read models of the automation, or errors | View tests in the read-model subfolder |

A translation slice uses the same table. It also gets mapper and codec tests
for its boundary DTOs.

Step 6: Run `dart format .`, `dart analyze`, and `dart test`. If a command
reports a problem, fix the generated code and run the command again. If
`map-event-model-hcl-to-code` runs a whole-model generation, it does this step
once at the end.
