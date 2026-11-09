# Read Event Modeling HCL into a Generation Inventory

This reference tells you how to read an Event Modeling HCL v0.8.0 (`.em.hcl`)
model into the generation inventory. This skill and the three slice skills use
the inventory.

## Contents

1. Validation first
2. Document model
3. References and ownership
4. Field model
5. Field sources
6. Lifecycles
7. Workflow kinds
8. Scenarios
9. Generation inventory
10. Slice names and collisions

Use the typed model from the `emhcl` CLI when it is available. The typed model
is the IR (intermediate representation) that emhcl makes after validation. Use
emhcl v0.17.0 or newer, which implements specification v0.8.0. Older releases
reject the v0.8.0 syntax. If the CLI is not available, read the HCL source with
the rules below. Report each reference that you cannot resolve before you
generate code.

## 1. Validation First

If the CLI is available, run validation before generation:

```bash
emhcl validate path/to/model.em.hcl
emhcl validate path/to/model-folder
```

The default profile is `valid`. If the user asks for strict validation, or the
target is production code, run `emhcl validate --profile strict <model>`. Do
not run `emhcl fmt -w` or `emhcl migrate -w` unless the user asks you to
rewrite the HCL source.

A core error (`EM000` to `EM305`) stops the generation. Judgment signals
(`EM401` to `EM406`) and hotspots are input for review. Do not turn them into
behavior unless a workflow, a scenario, or a lifecycle in the HCL already
defines that behavior.

## 2. Document Model

A model is one `.em.hcl` file or a folder of `.em.hcl` files. For a folder,
read every member file as one model. File names, file order, and block
positions have no meaning.

The required `board { workflows = [...] }` block gives the only story order.
Build the workflow inventory in board order. Then add the off-board workflows
in ID order. An off-board workflow is a workflow that the board does not list.
Off-board workflows are valid, and you must generate them. Chapters only group
workflows. Their list order does not change the inventory order. Keep the
written order of elements, fields, and scenario steps in each block, so that
the output stays stable.

Top-level blocks:

| HCL block | Use in generation |
| --------- | ----------------- |
| `board` | Story order of workflows for the inventory |
| `bounded_context` | Shared domain contracts in `lib/bounded_contexts/<name>/` |
| `lifecycle` | Lifecycle states in the bounded context of its aggregate, and decider rules. Section 6 gives the rules. |
| `actor`, `team`, `system` | Metadata for handlers, modules, external ownership, and access notes |
| `state_change`, `state_view`, `automation` | Slices. Section 7 names the slice skill for each kind. |
| `chapter` | Grouping only. It does not define code behavior. |
| `hotspot` | Review notes. Report each open hotspot on a generated element to the user. |
| `evidence_source`, `evidence`, `decision` | Records. They do not define code behavior. A `decision` on a generated element can become a doc comment. |

A hotspot with `kind = "assumption"` states a gap that the author filled. Code
that depends on it follows the model, but name the hotspot in the report. A
hotspot with `kind = "request"` asks for a model change. Do not make that
change in the code.

Block labels are lower-snake-case identities. Generated Dart identifiers come
from the label. A `title` is optional literal text. Use it only as written, for
example in doc comments and test names. Do not make a title from a label. If a
block has no title, generate no title.

## 3. References and Ownership

References are unquoted HCL traversals, not strings. Resolve each reference by
its kind:

```hcl
event.appointments.appointment_added
aggregate.appointments.appointment
field_type.appointments.appointment_id
command.add_appointment
command.add_appointment.add_appointment
processor.weather_translator
bounded_context.weather_provider
```

In a `bounded_context`, local references such as `aggregate.appointment` and
`field_type.appointment_id` refer to declarations in that context. Outside a
context, use the qualified forms. In a workflow, `<kind>.<id>` names an element
of the same workflow. `<kind>.<workflow>.<id>` names an element of the named
workflow. Lifecycles and records use this qualified form.

A field reference names one field of an element: the element reference, then
`.field.`, then the field name. Each subfield adds `.field.` and its name, for
example `command.open_booking.field.address.field.city`. It names a field
definition, not a value of one list item.

Each domain event belongs to the `bounded_context` that declares it. Workflow
elements do not own events. They refer to bounded-context events through
`from`, `to`, and scenario steps. Each command, read model, screen, and
processor belongs to the workflow that declares it.

## 4. Field Model

Generate Dart value objects and DTO fields from the declared HCL fields. Every
`field_type`, `field`, and `subfield` has an explicit `type`. A missing type is
a validation error (`EM009`). Do not infer a type from a field name.

Field declarations:

- `field_type` declares reusable vocabulary in a bounded context. It must have
  a built-in `type`.
- `field "<name>" { type = field_type.<context>.<name> }` uses the referenced
  field type.
- `field "<name>" { type = "<BuiltIn>" }` uses the built-in type directly.
- `fields = [field_type.<context>.<name>, ...]` declares one field for each
  entry. The last segment of the traversal gives the field name. The traversal
  gives the type.
- If a block has both `fields` and `field` blocks, the list fields come first.
  The `field` blocks follow in written order. A name never appears in both.
- `subfield` makes a compound value. Each `subfield` has its own `type`.

Built-in types map to these Dart types in generated value objects:

| HCL type | Wrapped Dart value |
| -------- | ------------------ |
| `String` | `String` |
| `Boolean` | `bool` |
| `Int`, `Long` | `int` |
| `Double` | `double` |
| `Decimal` | `String`, unless the target project already has a decimal type |
| `Date`, `DateTime` | `DateTime` |
| `UUID` | `String` |
| `Custom` | A named immutable Dart class or extension type, built from the declared fields |

If a field has `optional = true`, make the Dart field nullable. If a field has
`cardinality = "List"`, use `List<T>`. Keep `id_attribute`,
`technical_attribute`, `pii`, and `example` as generation metadata. Tag
extraction, codecs, fixtures, and DTO tests use this metadata.

An `aggregate` can declare `identity = field_type.<id>`. The identity is the
field type that names one stream of the aggregate. Each event of that
aggregate has a top-level field of this type. Use that field as the stream tag
of the aggregate: in event tags, in the repository queries of deciders, and in
the queries of views that read one stream. If the aggregate has no `identity`,
use the `id_attribute` fields.

Two key flags can appear on a `field` or a `subfield`:

| Flag | Use in generation |
| ---- | ----------------- |
| `correlation_key = true` | The value links an outside fact to an internal entity. A translation slice resolves the internal identity from it. |
| `deduplication_key = true` | A second delivery with the same value records no new fact. The consuming slice ignores a value that it already recorded. |

Do not infer a flag from a field name or from the `external` flag of a context.

## 5. Field Sources

A `field_source` block in a workflow states that one target field takes its
value from one or more input fields:

```hcl
field_source {
  inputs = [screen.booking_form.field.name]
  target = command.open_booking.field.guest_name
}
```

Use field sources to generate the mapping code between the elements of a
workflow. Each input connects to the target along one canonical flow edge:

| Input element -> target element | Generated mapping |
| ------------------------------- | ----------------- |
| screen -> command | DTO or UI input -> command, in `dto.dart` |
| command -> event | command -> emitted event, in the decider |
| event -> read model | event -> read-model state, in the View `evolve` |
| event -> processor | consumed event -> processor input, in the saga or the mapper |
| read model -> processor | read-model item -> processor input, in the saga |
| processor -> command | processor input -> sent command, in the saga or the mapper |
| read model -> screen | read-model state -> response or UI, in `dto.dart` |

With one input and no `description`, copy the value. If the types differ,
convert it with the value-object constructor of the target. With a
`description`, generate a named function that implements the stated rule, and
put the description in its doc comment. If the description does not state the
rule precisely enough to implement it, stop and ask the user.

A field without a `field_source` has no stated source. To generate working
code, copy the input field with the same name and the same type when exactly
one input element of the canonical edge has it. List each such inferred
mapping in the report to the user. If no input field matches, stop and ask the
user.

## 6. Lifecycles

A `lifecycle` states the states of the streams of one aggregate:

| HCL value | Use in generation |
| --------- | ----------------- |
| `lifecycle.aggregate` | The bounded context of this aggregate owns the lifecycle state type |
| `state` blocks | The values of the lifecycle state enum, in ID order |
| `transition` | The decider of `command` accepts the command in each `before` state, emits `events`, and its `evolve` moves the state to `after`. An empty `before` list means that the command starts a new stream. |
| `invalid_transition` | The decider of `command` rejects the command in each `before` state. `reason` is the error message. |
| `state.end` | No transition leaves this state in the model. Generate no extra check. |

Generate a rule only when a transition, an invalid transition, or a scenario
states it. If a command has a transition and the stream can be in a state
that is in no `before` list of that command, the model states no rule for that
state. Do not invent one. Report each such gap to the user.

A lifecycle adds no flow edge. If a transition names an event that is not in
the `to` list of its command, report the difference to the user and generate
the flow edges only.

## 7. Workflow Kinds

Each workflow kind has one canonical flow and one slice skill. Use the
source-to-target flow only.

| Workflow | Flow | Slice skill |
| -------- | ---- | ----------- |
| `state_change` | screen or external trigger -> command -> event | `map-state-change-hcl-to-code` |
| `state_view` | event -> readmodel -> screen | `map-state-view-hcl-to-code` |
| `automation` | event -> readmodel or processor -> command -> event | `map-automation-hcl-to-code` |

A `screen` is the interface of the system at one step. Its `kind` selects the
generated boundary code:

| Screen `kind` | Generated boundary code |
| ------------- | ----------------------- |
| `"ui"`, or no `kind` | UI code in the `ui/` folder of the slice |
| `"api"` | An API route in `handler.dart`. `api_endpoint` gives the method and the path, for example `"POST /pets"`. |

`actor` on a screen names the person or the partner system that uses it. Use
it for access notes in the handler.

A command has a reason: an incoming flow from a screen or a processor, or
`external_trigger = true`. `api_endpoint` on a command gives the route where
the code receives the command. It is not a reason by itself.

The HCL language has no `translation` keyword. The
`map-automation-hcl-to-code` skill decides if an `automation` is a
translation.

## 8. Scenarios

Workflow scenario blocks are the primary source for generated tests. Each step
has exactly one target. Steps can appear in any order in a scenario. Group the
steps by kind (`given`, `when`, `then`) and keep the written order in each
kind.

| Workflow | Given | When | Then |
| -------- | ----- | ---- | ---- |
| `state_change` | events | one command | events or an error |
| `state_view` | events, or none with `empty_history = true` | none | read models or an error |
| `automation`, action form | events or read models | one processor or command | events, errors, or commands (only when the `when` step is a processor) |
| `automation`, view form | events, or none with `empty_history = true` | none | read models of the same automation, or an error |

An `automation` scenario without a `when` step is a view form scenario. It
states the content of a read model of the automation, for example a to-do
list.

Scenario and step attributes:

| HCL value | Use in generation |
| --------- | ----------------- |
| `then { error = "..." }` | A test that expects the named rejection and no emitted events |
| `case` | The kind of the business rule. Use it to group and name the tests. Do not infer behavior from it. |
| `empty_history = true` | The read model before any event: the test checks the initial state of the View |
| `expect_empty_list = true` | The read model is an empty list |
| `then { command = ... }` | A dispatch assertion: the processor sends this command. Fields on the step give the command values. |
| `then { expect_no_dispatch = true, command = ... }` | The processor does not send this command in the given situation |
| `comment { description = ... }` | A note. Put it in a comment above the test. |

Scenario steps can carry fields and examples. If they do, use those values in
fixture builders and JSON round-trip tests. Each slice skill gives the
Given/When/Then rules for its workflow kind.

## 9. Generation Inventory

Before you edit code, make an internal inventory from the HCL:

- Bounded contexts, aggregates with their `identity`, field types, events, and
  event fields with their key flags.
- Lifecycles with their states, transitions, and invalid transitions.
- Event tags from aggregate identities, `id_attribute`, and the query fields
  of commands and read models.
- For each `state_change` workflow: commands, emitted events, aggregate
  references, screens with their `kind` and `api_endpoint`, external triggers,
  field sources, and the lifecycle rules of each command.
- For each `state_view` workflow: read models, consumed events, output screens
  with their `kind`, questions, and field sources.
- For each `automation` workflow: read models, processors, consumed events,
  sent commands, produced events, field sources, key flags, and the `external`
  value of the bounded context of each consumed event.
- Scenarios with their `case`, form, and fixture data in written order.
- The slice folder name of each slice (section 10).
- Open hotspots, decisions, and validation warnings on generated elements.

## 10. Slice Names and Collisions

All slices share one folder, `lib/slices/`. Give each slice a folder name:

| Slice | Folder name |
| ----- | ----------- |
| `state_change` workflow | The workflow label |
| Read model of a `state_view` workflow | The read-model label |
| `automation` workflow, including a translation | The workflow label |

Workflow labels are unique in a model. A read-model label can be equal to
another slice name. In that case, use `<workflow>_<readmodel>` as the folder
name of each colliding read-model slice. Tell the user the new folder names.

The subfolders of an automation slice use the labels of the commands and the
read models of that workflow. They are inside the slice folder, so they do not
collide with other slices.

If a required reference is not resolved, stop and report it to the user.
