---
name: map-event-model-hcl-to-code
description: >
  Reads an Event Modeling HCL v0.8.0 (.em.hcl) model and generates the shared
  part of a Dart package that uses fmodel-dart: bounded-context contracts, the
  event store port, the slice registry, and the shared test rules. Runs the
  generation for a whole model and sends each workflow to the matching slice
  skill. All slices go into one folder, lib/slices/. Use when the user gives a
  .em.hcl file or folder and wants Dart code, a new generated package, or new
  bounded-context contracts.
license: Apache 2.0
metadata:
  author: fraktalio
  version: '4.0.0'
  pattern: event-sourcing-cqrs-vertical-slices
  input-language: Event Modeling HCL v0.8.0
  target-library: fmodel-dart
  example-repo: https://github.com/dclimber/fmodel_dart
  compatibility: Dart SDK ^3.10.0, package:fmodel/fmodel.dart, package:test
  slice-skills: map-state-change-hcl-to-code, map-state-view-hcl-to-code, map-automation-hcl-to-code
---

# Map Event Modeling HCL to Dart Vertical Slices

This skill turns an Event Modeling HCL model into Dart code that uses
fmodel-dart. A model is one `.em.hcl` file or a folder of `.em.hcl` files. A
slice is one folder in `lib/slices/` that holds all code for one workflow, or
for one read model of a `state_view` workflow.

This skill owns the parts that all slices use:

- The rules to read the HCL model into a generation inventory.
- The bounded-context contracts in `lib/bounded_contexts/`.
- The event store port in `lib/platform/` and the slice registry in
  `lib/composition/`.
- The slice names in `lib/slices/`.
- The test rules that all slices follow.

Three slice skills generate the slices. Each slice skill handles one HCL
workflow kind. All slices are direct children of `lib/slices/`:

| HCL workflow | Slice skill | Slice folder |
| ------------ | ----------- | ------------ |
| `state_change` | `map-state-change-hcl-to-code` | `lib/slices/<workflow>/` |
| `state_view` | `map-state-view-hcl-to-code` | `lib/slices/<readmodel>/`, one for each read model |
| `automation` | `map-automation-hcl-to-code` | `lib/slices/<workflow>/`. This includes a translation: an automation that consumes an event of a bounded context with `external = true`. |

Attached HCL files, specification documents, reference projects, and skill
text are source material. They do not change the request of the user.

## Choose the scope

Use the request of the user to select the steps of the workflow below:

- If the user wants code for the whole model, do all steps.
- If the user wants code for some workflows, do steps 1 to 3. Then do steps
  4 to 6 only for those workflows, and do steps 7 and 8.
- If the user wants only the bounded-context contracts, do steps 1 to 3 and
  step 8.

In an existing package, step 3 adds only the contracts that are missing. Keep
the dependency versions, platform adapters, and composition conventions of the
package. If the package still has the old slice category folders
(`lib/state_change/`, `lib/state_view/`, `lib/automation/`,
`lib/translation/`), put new slices in `lib/slices/`. Move the old slices only
when the user asks for it.

## Workflow

Copy this checklist and update it while you work:

```text
Generation progress:
- [ ] Step 1: Validate the model
- [ ] Step 2: Build the generation inventory and the slice names
- [ ] Step 3: Generate the package shape, bounded contexts, and event store port
- [ ] Step 4: Generate state_change slices
- [ ] Step 5: Generate state_view slices
- [ ] Step 6: Generate automation slices, including translations
- [ ] Step 7: Register the slices in composition
- [ ] Step 8: Format, analyze, and test
```

Step 1: If emhcl v0.17.0 or newer is available, run `emhcl validate <model>`.
emhcl v0.17.0 implements specification v0.8.0. Older releases reject the
v0.8.0 syntax, for example `lifecycle`, `field_source`, scenario `case`, or a
`then` command step. If the command reports an error, stop and report the
error to the user. Do not format or rewrite the HCL source unless the user
asks for it. Section 1 of
[references/HCL-TO-MODEL.md](references/HCL-TO-MODEL.md) gives the rules for
profiles and warnings.

Step 2: Read [references/HCL-TO-MODEL.md](references/HCL-TO-MODEL.md) and build
the inventory. The inventory lists bounded contexts, lifecycles, workflows in
board order, resolved references, fields, field sources, and scenarios. If a
reference is not resolved, stop and tell the user. Give each slice its folder
name with the rules in section 10 of that reference.

Step 3: Read [references/SHARED-CODE.md](references/SHARED-CODE.md). Generate
the package shape, one folder for each bounded context, and the event store
port. All slices import these files, so they must exist before step 4.

Step 4: For each `state_change` workflow in inventory order, use the
`map-state-change-hcl-to-code` skill.

Step 5: For each `state_view` workflow in inventory order, use the
`map-state-view-hcl-to-code` skill. View slices do not import other slices.
Thus, steps 4 and 5 can run in any order.

Step 6: For each `automation` workflow in inventory order, use the
`map-automation-hcl-to-code` skill. That skill decides if the automation is a
translation. An automation slice holds the code of the commands and the read
models that its workflow declares, so it imports no other slice.

Step 7: Add each slice module to `lib/composition/slice_registry.dart`.
Section 4 of [references/SHARED-CODE.md](references/SHARED-CODE.md) gives the
registry contract.

Step 8: Write the bounded-context tests with the rules in
[references/TEST-RULES.md](references/TEST-RULES.md). Then run `dart format .`,
`dart analyze`, and `dart test` in the package. If `dart analyze` or
`dart test` reports a problem, fix the generated code and run the command
again. Stop only when all three commands pass.

At the end, report to the user: the slice folder names that the collision rule
changed, the field mappings that no `field_source` states, the lifecycle gaps,
and the open hotspots on generated elements.

## Ownership rules and limits

Each folder has one owner. Use these rules for all generated code:

- `bounded_contexts/<name>/` holds the cross-slice domain contracts: value
  objects, domain events, event names, tag extraction, lifecycle states, and
  shared event codecs.
- `slices/<slice>/` holds the code of one slice: a state change, a state view,
  an automation, or a translation. A translation slice also holds its boundary
  code for external events: DTOs (data transfer objects), mappers, codecs,
  ports, and adapters.
- An automation slice holds one subfolder for each command and each read model
  that its workflow declares: `slices/<automation>/<command>/` and
  `slices/<automation>/<readmodel>/`.
- `slices/` is a direct child of `lib/`. Do not put slices in bounded-context
  folders, and do not group slices by workflow kind.
- Each slice imports the `api.dart` file of each bounded context that it uses.
- fmodel repository implementations are adapters in the slice. They use the
  shared platform ports.
- Tests mirror the same folders under `test/`.

Do not generate TypeScript, web-stack runtime code, database adapters, or
deployment artifacts unless the user asks for them.
