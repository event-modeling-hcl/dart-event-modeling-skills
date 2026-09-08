# Event Modeling HCL to Generation Model

This reference covers reading Event Modeling HCL v0.3.0 (`.em.hcl`) into the
model used for Dart code generation.

Prefer the validated typed model / IR produced by the `eventmodeling-hcl`
tooling. If the CLI is unavailable, inspect the HCL source against these rules
and surface unresolved references before generating code.

## 1. Validation First

Run validation before generation when the CLI is available:

```bash
eventmodeling-hcl validate --profile valid path/to/model.em.hcl
```

Use `--profile strict` when the user asks for strict validation or when the
target is production-grade code. Do not run `fmt -w` unless the user explicitly
asks to rewrite the HCL source.

Treat structural validation errors as blockers for generation. Treat warnings
and hotspots as review input; do not turn them into behavior unless the HCL
workflow/scenario already defines that behavior.

## 2. Document Model

One `.em.hcl` file is one Event Model document. Preserve source order for
bounded contexts, workflows, workflow elements, and scenario steps.

Top-level block categories:

| HCL block | Generation use |
| --------- | -------------- |
| `bounded_context` | Shared domain contracts under `lib/bounded_contexts/<name>/` |
| `actor`, `team`, `system` | Metadata for handlers, modules, external ownership, and access notes |
| `state_change` | Command-handling slices under `lib/state_change/<use_case>/` |
| `state_view` | Read-model slices under `lib/state_view/<read_model>/` |
| `automation` | Internal reaction slices under `lib/automation/<process_or_policy>/` |
| `translation` | External-boundary slices under `lib/translation/<external_boundary>/` |
| `chapter`, `hotspot` | Workshop metadata and review notes, not code behavior by themselves |
| `relationship` | Optional context-map metadata if the proposed RFC surface is present |

Block labels are lower-snake-case identities. Derive display titles from labels
when `title` is absent, but keep generated Dart identifiers based on the stable
label identity.

## 3. References And Ownership

References are unquoted HCL traversals, not strings. Resolve them by kind:

```hcl
event.appointments.appointment_added
aggregate.appointments.appointment
field_type.appointments.appointment_id
command.add_appointment
processor.weather_translator
bounded_context.weather_provider
```

Inside a `bounded_context`, local references such as `aggregate.appointment` and
`field_type.appointment_id` refer to declarations in that context. Outside a
context, use the qualified forms.

Each concrete domain event belongs to the `bounded_context` that declares it.
Workflow-local elements do not own events; they reference bounded-context event
contracts through `from`, `to`, and scenario steps.

## 4. Field Model

Generate Dart value objects and DTO fields from the effective HCL fields after
field shorthand is resolved.

Field sources:

- `field_type` declares reusable vocabulary in a bounded context and must have a
  built-in `type`.
- `field "<name>" { type = field_type.<...> }` uses the referenced field type.
- `field "<name>" {}` infers the same-named `field_type`; event and subfield
  fields resolve in their owning context, while workflow-element fields resolve
  by unique document-wide name.
- `fields = [field_type.<context>.<name>, ...]` expands to fields named after
  the final traversal segment.
- If both `fields` and `field` blocks are present, list fields come first and
  explicit field blocks follow in source order.
- `subfield` creates a compound value shape.

Built-in type defaults for generated Dart value objects:

| HCL type | Wrapped Dart value |
| -------- | ------------------ |
| `String` | `String` |
| `Boolean` | `bool` |
| `Int`, `Long` | `int` |
| `Double` | `double` |
| `Decimal` | `String` unless the target project already has a decimal type |
| `Date`, `DateTime` | `DateTime` |
| `UUID` | `String` |
| `Custom` | A named immutable Dart class or extension type based on declared fields |

Honor `optional = true` with nullable Dart fields. Honor `cardinality = "List"`
with `List<T>`. Preserve `id_attribute`, `technical_attribute`, `pii`, and
`example` as generation metadata for tag extraction, codecs, fixtures, and DTO
tests.

## 5. Workflow Flows

Use canonical source-to-target flow only.

### State Change

State change workflows model intent becoming facts:

```text
screen/API/external trigger -> command -> event
```

Read `screen.to`, `command.to`, command `api_endpoint`, and
`external_trigger`. A command must have an incoming flow, API endpoint, or
explicit external trigger. Generate one `state_change/<use_case>/` slice per
workflow by default; split only when the HCL workflow contains independent
commands that do not share the same use case.

### State View

State view workflows model facts becoming an answer:

```text
event -> readmodel -> screen/API
```

Read `readmodel.from`, `readmodel.to`, and required `question`. Generate one
`state_view/<read_model>/` slice per read model. If multiple workflows define
the same read-model label, prefix the folder with the workflow or bounded
context label.

Event Modeling read models map to `fmodel-dart` `View<S, E>` components.

### Automation

Automation workflows model internal machine reactions:

```text
internal event -> readmodel/processor -> command -> event
```

Read `readmodel.from`, `readmodel.to`, `processor.from`, `processor.to`, and
`command.to`. Generate `Saga<AR, A>` based reactions for event-to-command
policies, and route emitted commands to the owning state-change slice.

Automation should not consume events from an external bounded context. If it
does, model it as translation or surface the mismatch.

### Translation

Translation workflows model external-language facts crossing a boundary:

```text
external event -> readmodel/processor -> command -> internal event
```

At least one consumed event should come from `bounded_context` with
`external = true`. Generate boundary DTOs, codecs, anti-corruption mappers,
ports/adapters, and reaction wiring in `translation/<external_boundary>/`.

Keep translated internal events in their owning bounded context, not in the
translation slice.

## 6. Scenarios To Tests

Use workflow-local `scenario` blocks as the primary source for generated tests.

Pattern rules:

| Workflow | Scenario shape | Generated tests |
| -------- | -------------- | --------------- |
| `state_change` | Given events, exactly one When command, Then events or errors | Decider/service/handler tests |
| `state_view` | Given events, no When, Then readmodel or errors | View/repository/service tests |
| `automation` | Given event/readmodel, exactly one When processor or command, Then events or errors | Saga/manager tests |
| `translation` | Given external event/readmodel, exactly one When processor or command, Then internal event or errors | Mapper/saga/handler tests |

Scenario steps may carry fields and examples. Use those values for fixture
builders and JSON round-trip tests when present.

## 7. Generation Inventory

Before editing code, create an internal inventory from the HCL:

- bounded contexts, aggregates, field types, events, and event fields;
- event tags derived from `id_attribute`, aggregate IDs, and command/read-model
  query fields;
- state-change workflows, commands, emitted events, aggregate references, API
  endpoints, and external triggers;
- state-view read models, consumed events, output screens, and questions;
- automation processors/read models, consumed events, emitted commands, and
  produced events;
- translation external contexts, external events, internal commands/events, and
  boundary names;
- scenarios and fixture data in source order;
- hotspots or validation warnings that affect generation.

If a required reference is unresolved or a slice name collides, stop and make
the ambiguity explicit. Resolve collisions by prefixing the slice folder with a
bounded-context or workflow label, for example `restaurant_create` or
`ordering_create`.
