# Translation Slice Code

This reference gives the shape of a translation slice. A translation is an
automation that consumes at least one event of a bounded context with
`external = true`. A translation slice brings facts from that external
bounded context into the internal language. It is an anti-corruption layer:
code that keeps external data shapes out of the internal domain.

A translation slice has this flow:

```text
external event -> readmodel or processor -> command -> internal event
```

The folder is `lib/slices/<workflow>/`, like every other slice. A translation
slice has the layout of an automation slice, plus its boundary files:

```text
lib/slices/<workflow>/
  dto.dart
  mapper.dart
  codec.dart
  port.dart
  adapter.dart
  saga.dart
  processor_state.dart
  publisher.dart
  service.dart
  handler.dart
  module.dart
  <command>/
  <readmodel>/
```

## Files

Each file has one responsibility:

| File | Content |
| ---- | ------- |
| `dto.dart` | The external data shapes, with parse and encode functions |
| `mapper.dart` | Converts external DTOs into the values of the internal language, with the `field_source` rules |
| `codec.dart` | Codecs that only this external boundary needs |
| `port.dart` | The contract of an external service or a lookup, when the slice must call out |
| `adapter.dart` | Implements a port with a concrete client or platform service |
| `saga.dart`, `processor_state.dart` | The processor, with the rules of `references/AUTOMATION.md` |
| `handler.dart` | Receives the external event, maps it, resolves the correlation key, and passes the input to the saga manager |
| `publisher.dart`, `service.dart`, `module.dart` | As in an automation slice |

## Key Flags

Use the key flags of the consumed external event fields:

- `correlation_key = true`: the value links the external fact to an internal
  entity. If a `field_source` maps the field to the internal identity field,
  apply that mapping in `mapper.dart`. Otherwise generate a lookup port in
  `port.dart` that returns the internal identity for the correlation value,
  and an in-memory adapter in `adapter.dart`. Report the lookup port to the
  user. If the lookup finds no entity, the handler sends no command and
  returns a boundary error.
- `deduplication_key = true`: a second delivery with the same value records no
  new fact. The processor state holds the values that the slice already
  recorded (`references/AUTOMATION.md`, section 3). A repeated value sends no
  command.

## Rules

Follow these rules for each translation slice:

- Generate a file only when the model or the user request needs it.
- Do not put business decisions in the mapper, the DTOs, or the adapters.
  Business decisions belong in deciders, views, and sagas.
- Keep domain events and value objects in `bounded_contexts/<name>/`. The
  internal events that the translation produces stay in their owning bounded
  context.
- The command classes come from the command subfolders of the slice.
- If more than one slice uses a codec, put it in the bounded context, not in
  the translation slice.
