---
name: map-state-view-hcl-to-code
description: >
  Generates one Dart state-view slice in lib/slices/ with fmodel-dart for each
  read model of a state_view workflow in an Event Modeling HCL v0.8.0
  (.em.hcl) model. The slice holds the query, read-model state, View, view
  repository, service, handler, module, and tests. Use when the user wants
  Dart code for a state_view workflow, a read model, a projection, or a query
  from a .em.hcl model, or adds a state_view workflow to a package that
  map-event-model-hcl-to-code generated.
license: Apache 2.0
metadata:
  author: fraktalio
  version: '2.0.0'
  pattern: event-sourcing-read-model-slice
  input-language: Event Modeling HCL v0.8.0
  target-library: fmodel-dart
  example-repo: https://github.com/dclimber/fmodel_dart
  compatibility: Dart SDK ^3.10.0, package:fmodel/fmodel.dart, package:test
  requires-skill: map-event-model-hcl-to-code
---

# Map an HCL State View to a Dart Slice

This skill generates state-view slices from one `state_view` workflow. A
state-view slice is the folder `lib/slices/<readmodel>/`. It holds all
code that turns stored events into the answer to one question. A read model is
the data that answers that question. In fmodel-dart, a `View<S, E>` folds
events of type `E` into a read-model state of type `S`. To fold is to apply the
events one by one to the state.

## Before you start

This skill uses the reading rules and the shared code of the
`map-event-model-hcl-to-code` skill. Make sure that these conditions are true:

1. You have the generation inventory of the model. The
   `references/HCL-TO-MODEL.md` file of `map-event-model-hcl-to-code` tells
   you how to build it.
2. `lib/bounded_contexts/<context>/api.dart` exists for each bounded context
   that the workflow uses. It contains each event that the read model consumes.
3. `lib/platform/event_store/event_store.dart` exists.

If a condition is false, use the `map-event-model-hcl-to-code` skill first.
Then come back to this skill.

## Read the workflow

A `state_view` workflow has this flow:

```text
event -> readmodel -> screen
```

Read these HCL values:

| HCL value | Use in the slice |
| --------- | ---------------- |
| `readmodel.from` | The events that the repository loads and that the View folds |
| `readmodel.question` | The test names. The read-model state holds only the answer to this question. |
| `readmodel` fields | The fields of the read-model state |
| `field_source` blocks | The mapping from event fields to read-model fields in the View, and from read-model fields to screen fields in the DTO |
| `readmodel.to`, screen `kind`, `api_endpoint`, `actor` | The DTO, the handler, the UI, and the module |
| `scenario` blocks | The tests |

An API screen (`kind = "api"`) is the response that a client reads. It gives
an API route in `handler.dart`. A UI screen (no `kind`, or `kind = "ui"`)
gives UI code in `ui/`.

Generate one slice for each `readmodel` block. The folder name is the
read-model label. If that name collides with another slice in `lib/slices/`,
use the collision rule of `map-event-model-hcl-to-code`:
`<workflow>_<readmodel>`.

A state-view slice does not import code from other slices. Do not add
relationships that the resolved HCL references do not contain.

The `map-automation-hcl-to-code` skill also uses this skill for the read model
of an automation, for example a to-do list. For that read model, the target
folder is `lib/slices/<automation>/<readmodel>/`, and each relative import gets
one more `../`. Generate `query.dart`, `state.dart`, `view.dart`,
`repository.dart`, and `service.dart`. Generate no DTO, handler, UI, or
module. The tests come from the view form scenarios of the automation.

## Ephemeral or materialized

An ephemeral view folds the events each time that a query arrives. A
materialized view stores the read-model state and updates it for each new
event. Generate an ephemeral view by default. Generate a materialized view only
when the user asks for a stored read-model state, or the project already uses
materialized views.

## Slice files

Generate only the files that the model or the user request needs:

| File | Content |
| ---- | ------- |
| `query.dart` | The query type, usually the ID value object of the read model |
| `state.dart` | The read-model state with value equality |
| `view.dart` | The `View<S, E>` with `initialState` and `evolve` |
| `repository.dart` | The `EphemeralViewRepository` adapter, or the `ViewStateRepository` adapter for a materialized view |
| `service.dart` | Builds the view and the repository from the `EventStore` port, and answers queries |
| `dto.dart` | Encodes the read-model state for the screen |
| `handler.dart` | Receives the query and returns the encoded read model. Holds the API route of an API screen. |
| `module.dart` | Registers the routes and UI parts of the slice with composition |
| `ui/` | UI code for each UI screen of the workflow |

## Workflow

Copy this checklist and update it while you work:

```text
State-view slice progress:
- [ ] Step 1: Make sure that the conditions in "Before you start" are true
- [ ] Step 2: Select an ephemeral or a materialized view
- [ ] Step 3: Generate the query, the state, and the View
- [ ] Step 4: Generate the repository and the service
- [ ] Step 5: Generate the DTO, the handler, and the module
- [ ] Step 6: Generate the tests and the property laws
- [ ] Step 7: Format, analyze, and test
```

Steps 3 to 5: Read [references/CODE.md](references/CODE.md). It gives the code
shape for each file. The View folds only the events in `readmodel.from`. Map
the fields with the `field_source` blocks of the workflow. Section 5 of
`references/HCL-TO-MODEL.md` of `map-event-model-hcl-to-code` gives the rules
for fields without a source.

Step 6: Read [references/TESTS.md](references/TESTS.md) and the shared rules in
the `references/TEST-RULES.md` file of `map-event-model-hcl-to-code`. Map the
scenarios of the workflow with this table:

| Given | When | Then | Generated tests |
| ----- | ---- | ---- | --------------- |
| one or more events | none | one or more read models or errors | View, repository, and service tests |
| none, with `empty_history = true` | none | one or more read models or errors | A View test of the initial state |

Step 7: Run `dart format .`, `dart analyze`, and `dart test`. If a command
reports a problem, fix the generated code and run the command again. If
`map-event-model-hcl-to-code` runs a whole-model generation, it does this step
once at the end.
