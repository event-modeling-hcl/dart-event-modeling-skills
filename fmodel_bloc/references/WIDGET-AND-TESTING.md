# Widget Wiring and Testing

This file covers the last two layers of the seam: the **flutter_bloc widget layer** that reads
`UiState` and sends intents, and **testing the presentation layer** with `bloc_test`. It assumes
the Cubit/Bloc already exists — see [CUBIT-INTEGRATION.md](CUBIT-INTEGRATION.md) or
[BLOC-INTEGRATION.md](BLOC-INTEGRATION.md) for that. The running example is the Wardrobe /
add-item screen used throughout this skill.

## Table of contents

1. Dependency injection: `RepositoryProvider` + `BlocProvider`
2. Rendering state: `BlocBuilder`, `BlocSelector`, `context.select`
3. Side effects: `BlocListener` and `BlocConsumer`
4. Sending intents from widgets
5. Testing with `bloc_test`
6. Aligning with fmodel's given/when/then domain tests
7. Common mistakes recap

## 1. Dependency injection: `RepositoryProvider` + `BlocProvider`

The widget tree needs two things above the screen: the fmodel **application service** (a single
collaborator wrapping the aggregate/view — never the aggregate or repository directly) and the
**Cubit/Bloc** that depends on it. `flutter_bloc` gives you one provider for each concern:

- `RepositoryProvider<T>({required T Function(BuildContext) create, Widget? child})` — injects a
  plain object (here, `WardrobeService`) that is *not* a Cubit/Bloc. It does not listen to a
  stream and does not rebuild anything by itself; it exists purely so descendants can
  `context.read<WardrobeService>()`.
- `BlocProvider<T>({required T Function(BuildContext) create, Widget? child, bool lazy = true})`
  — creates the Cubit/Bloc via `create`, exposes it to descendants, and **closes it automatically**
  when the provider is removed from the tree. `lazy: true` (the default) defers `create` until the
  bloc is first read/watched.
- `BlocProvider.value({required T value, Widget? child})` — hands down an **already-constructed**
  instance (e.g. one owned further up the tree, or injected in a test). Because the provider did
  not create it, it does **not** close it on disposal — the owner is responsible for that. Reach
  for `.value` when passing an existing bloc across a route boundary (e.g. into a new
  `MaterialPageRoute`); reach for the `create` constructor everywhere else.
- `BlocProvider.of<T>(context)` is the explicit form of `context.read<T>()`; prefer the extension.

Compose the two with `MultiRepositoryProvider`/`MultiBlocProvider` when a screen needs several,
but a single pair is enough for Wardrobe:

```dart
// presentation/wardrobe_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/wardrobe_service.dart';
import 'add_item/add_item_cubit.dart';
import 'wardrobe_view.dart';

class WardrobePage extends StatelessWidget {
  const WardrobePage({super.key, required this.service});

  // Constructed once, above this screen (e.g. in main.dart or a parent route),
  // and handed down — this widget does not build the service itself.
  final WardrobeService service;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<WardrobeService>.value(
      value: service,
      child: BlocProvider<AddItemCubit>(
        // The Cubit's only collaborator is the injected service — it never
        // constructs an aggregate, a repository, or an event store itself.
        create: (ctx) => AddItemCubit(ctx.read<WardrobeService>()),
        child: const WardrobeView(),
      ),
    );
  }
}
```

`WardrobeView` is a plain `StatelessWidget`/`StatefulWidget` that only ever imports
`add_item_cubit.dart` and Flutter — never the domain or application layer. That boundary is what
lets `WardrobeView` be tested with a fake service standing in for `WardrobeService` (Section 5)
without touching persistence.

## 2. Rendering state: `BlocBuilder`, `BlocSelector`, `context.select`

`BlocBuilder<B, S>` rebuilds its `builder` every time the bloc emits a new state (subject to
`buildWhen`). Switch on `AddItemStatus` to decide what to render — this is where the `UiState`'s
status field earns its keep:

```dart
class WardrobeView extends StatelessWidget {
  const WardrobeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wardrobe')),
      body: BlocBuilder<AddItemCubit, AddItemUiState>(
        // Skip rebuilds that only change the error message while loading.
        buildWhen: (previous, current) => previous.status != current.status,
        builder: (context, state) {
          return switch (state.status) {
            AddItemStatus.initial => const _AddItemForm(),
            AddItemStatus.loading => const Center(child: CircularProgressIndicator()),
            AddItemStatus.success => _WardrobeList(items: state.wardrobe?.items ?? const []),
            AddItemStatus.failure => _WardrobeList(
                items: state.wardrobe?.items ?? const [],
                banner: state.error,
              ),
          };
        },
      ),
    );
  }
}
```

Use `BlocSelector<B, S, T>` when a widget only cares about a slice of `UiState` — it rebuilds
only when the *selected* value changes, not on every status flip:

```dart
BlocSelector<AddItemCubit, AddItemUiState, int>(
  selector: (state) => state.wardrobe?.items.length ?? 0,
  builder: (context, itemCount) => Text('$itemCount items'),
)
```

`context.select<B, T>((bloc) => ...)` is the inline equivalent, handy inside a larger `build`
method when a whole `BlocSelector` widget would be overkill:

```dart
final itemCount = context.select<AddItemCubit, int>(
  (cubit) => cubit.state.wardrobe?.items.length ?? 0,
);
```

Both `BlocSelector` and `context.select` come from `flutter_bloc`/`provider` and use `==` to
decide whether to rebuild — another reason `UiState` (and any type nested inside it, like
`WardrobeViewState`) must have value equality via `Equatable`. Without it, every emission looks
"different" and every selector rebuilds regardless of what actually changed.

## 3. Side effects: `BlocListener` and `BlocConsumer`

Anything that should happen **once** per state change and is not itself a render — a `SnackBar`,
a navigation push, a focus change — belongs in `BlocListener`, not `BlocBuilder`. Listeners run
side effects; builders return widgets. Mixing them (e.g. calling `ScaffoldMessenger.of(context)`
inside a `builder`) fires on every rebuild, not just on the transition that matters.

```dart
BlocListener<AddItemCubit, AddItemUiState>(
  listenWhen: (previous, current) => previous.status != current.status,
  listener: (context, state) {
    switch (state.status) {
      case AddItemStatus.failure:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error ?? 'Could not add item')),
        );
      case AddItemStatus.success:
        Navigator.of(context).maybePop();
      case AddItemStatus.initial:
      case AddItemStatus.loading:
        break;
    }
  },
  child: const _AddItemForm(),
)
```

When a screen needs both a rebuild and a side effect from the same stream, `BlocConsumer<B, S>`
combines `builder` and `listener` (each with its own `buildWhen`/`listenWhen`) without nesting two
widgets:

```dart
BlocConsumer<AddItemCubit, AddItemUiState>(
  listenWhen: (previous, current) => current.status == AddItemStatus.failure,
  listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(state.error ?? 'Could not add item')),
  ),
  buildWhen: (previous, current) => previous.status != current.status,
  builder: (context, state) => state.status == AddItemStatus.loading
      ? const CircularProgressIndicator()
      : const _AddItemForm(),
)
```

## 4. Sending intents from widgets

A button `onPressed` sends the raw form data as an intent — it never builds an fmodel `Command`
itself; the Cubit/Bloc owns that translation (step 2 of the seam in `SKILL.md`). Use
`context.read<T>()` inside callbacks, never `context.watch<T>()`: `watch` subscribes the enclosing
widget to rebuilds and is only valid inside `build`; in a callback you just want the instance, so
`read` is correct and avoids an unnecessary listener.

Cubit path — a direct method call:

```dart
ElevatedButton(
  onPressed: () {
    context.read<AddItemCubit>().addItem(
          name: nameController.text,
          category: categoryController.text,
        );
  },
  child: const Text('Add'),
)
```

Bloc path — dispatch a `UiEvent` case with `add`:

```dart
ElevatedButton(
  onPressed: () {
    context.read<AddItemBloc>().add(
          AddItemSubmitted(
            name: nameController.text,
            category: categoryController.text,
          ),
        );
  },
  child: const Text('Add'),
)
```

Either way, `_AddItemForm` imports only `add_item_cubit.dart` (or `add_item_bloc.dart` +
`add_item_ui_event.dart`) and Flutter. It does not import `AddItemCommand` or any domain type —
if a widget needs to construct a `Command`, that is a layering defect; move the construction into
the Cubit/Bloc.

## 5. Testing with `bloc_test`

Test the Cubit/Bloc against a **fake** `WardrobeService` — a hand-written fake implementing the
service's interface, or a `mocktail` mock — never against a real aggregate or event store. The
fake lets the test drive exactly two scenarios: the service resolves, or it throws a `DomainError`.

```dart
// test/presentation/add_item/fake_wardrobe_service.dart
import '../../../lib/application/wardrobe_service.dart';
import '../../../lib/state_change/add_item/api.dart';   // AddItemCommand, DomainError
import '../../../lib/state_view/wardrobe_view/api.dart'; // WardrobeViewState

class FakeWardrobeService implements WardrobeService {
  FakeWardrobeService({this.throwOnHandle, this.viewToReturn});

  final DomainError? throwOnHandle;
  final WardrobeViewState? viewToReturn;

  @override
  Future<void> handle(AddItemCommand command) async {
    if (throwOnHandle != null) throw throwOnHandle!;
  }

  @override
  Future<WardrobeViewState> wardrobe() async =>
      viewToReturn ?? const WardrobeViewState(items: []);
}
```

`blocTest<B, S>('description', {build, seed, act, skip, wait, expect, verify, errors,
tearDown, tags})` builds the bloc fresh per case, runs `act`, and asserts the emitted state
sequence against `expect` using `==` — which is exactly why `AddItemUiState` needs `Equatable`;
without it, two states with identical fields still compare unequal and every `expect` fails.

```dart
// test/presentation/add_item/add_item_cubit_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/presentation/add_item/add_item_cubit.dart';
import '../../../lib/state_change/add_item/api.dart'; // DomainError subtype
import 'fake_wardrobe_service.dart';

void main() {
  group('AddItemCubit', () {
    blocTest<AddItemCubit, AddItemUiState>(
      'emits [loading, success] when the service resolves',
      build: () => AddItemCubit(
        FakeWardrobeService(
          viewToReturn: const WardrobeViewState(items: ['Blue Shirt']),
        ),
      ),
      act: (cubit) => cubit.addItem(name: 'Blue Shirt', category: 'Tops'),
      expect: () => [
        const AddItemUiState(status: AddItemStatus.loading),
        const AddItemUiState(
          status: AddItemStatus.success,
          wardrobe: WardrobeViewState(items: ['Blue Shirt']),
        ),
      ],
    );

    blocTest<AddItemCubit, AddItemUiState>(
      'emits [loading, failure] when the service throws a DomainError',
      build: () => AddItemCubit(
        FakeWardrobeService(throwOnHandle: const ItemAlreadyExistsError('Blue Shirt')),
      ),
      act: (cubit) => cubit.addItem(name: 'Blue Shirt', category: 'Tops'),
      expect: () => [
        const AddItemUiState(status: AddItemStatus.loading),
        isA<AddItemUiState>()
            .having((s) => s.status, 'status', AddItemStatus.failure)
            .having((s) => s.error, 'error', isNotNull),
      ],
    );
  });
}
```

The same fake drives a `Bloc` test; the only difference is `act` dispatches a `UiEvent` with
`add` instead of calling a method directly:

```dart
// test/presentation/add_item/add_item_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/presentation/add_item/add_item_bloc.dart';
import 'fake_wardrobe_service.dart';

void main() {
  group('AddItemBloc', () {
    blocTest<AddItemBloc, AddItemUiState>(
      'emits [loading, success] when AddItemSubmitted is added and the service resolves',
      build: () => AddItemBloc(
        FakeWardrobeService(
          viewToReturn: const WardrobeViewState(items: ['Blue Shirt']),
        ),
      ),
      act: (bloc) => bloc.add(
        const AddItemSubmitted(name: 'Blue Shirt', category: 'Tops'),
      ),
      expect: () => [
        const AddItemUiState(status: AddItemStatus.loading),
        const AddItemUiState(
          status: AddItemStatus.success,
          wardrobe: WardrobeViewState(items: ['Blue Shirt']),
        ),
      ],
    );
  });
}
```

`seed` is useful when a case should start from a non-initial `UiState` (e.g. asserting a second
submission's transitions without re-emitting the first); `wait` and `skip` help with debounced or
transformer-based Blocs (see `BLOC-INTEGRATION.md`); `verify` is the place to assert the fake was
called with the expected `AddItemCommand`, if that matters to the case.

## 6. Aligning with fmodel's given/when/then domain tests

fmodel-dart ships its own test DSL for the **domain** layer — `Decider`/`View` extension methods
used as `await decider.givenEvents([...]).whenCommand(AddItemCommand(...)).thenEvents([...])`.
That DSL asserts domain rules: given this event history, this command yields exactly these
domain events (or is rejected). It belongs in the domain/application test suite that ships with
the upstream `map-event-model-hcl-to-code` output, not here.

The presentation-layer tests in this file are deliberately narrower. Against a **fake** service,
`blocTest` verifies only the seam this skill adds:

- the intent is translated into the right shape of call to the service (a `Command` was built
  and handed off — `verify` can assert this against the fake);
- the resulting `UiState` sequence matches the status/data mapping (`loading` → `success` with
  the projection, or `loading` → `failure` with an error).

It does **not** re-verify *why* `AddItemCommand(name: 'Blue Shirt', category: 'Tops')` produces
`ItemAddedEvent` rather than `ItemAlreadyExistsError` — that is a domain rule, already proven by
the decider's own given/when/then tests. Duplicating it here through a real aggregate would mean
two suites re-asserting the same rule through different, slower paths, and a domain-rule change
would break presentation tests that have nothing to do with presentation logic. Keep the fake
dumb (return a fixed view, or throw a fixed error) and let the domain suite own correctness of
the business rule.

## 7. Common mistakes recap

- **A widget importing domain types.** If `_AddItemForm` needs to import `AddItemCommand` or
  `WardrobeEvent`, the Cubit/Bloc is missing a method/case that should own that construction.
  Widgets know only `UiState`/`UiEvent`.
- **`context.watch<T>()` inside a callback.** `watch` is for `build` only; it registers a
  dependency that a one-shot `onPressed` callback never needs. Use `context.read<T>()` in
  callbacks.
- **Re-testing domain rules through the bloc with a real aggregate.** Slow, duplicated, and it
  makes presentation tests fail for domain reasons. Use a fake service and let the domain's
  given/when/then suite own business-rule correctness (Section 6).
- **Forgetting `Equatable` on `UiState` (or a nested type like `WardrobeViewState`).** `blocTest`'s
  `expect` and `BlocBuilder`/`BlocSelector`'s rebuild logic both compare by `==`. Without value
  equality, identical-looking states never match and tests fail, or widgets rebuild on every
  emission regardless of `buildWhen`/`selector`.
- **Doing side effects in `builder` instead of `listener`.** A `SnackBar` or navigation call
  inside `BlocBuilder.builder` reruns on every rebuild, not just the transition that triggered it
  — use `BlocListener`/`BlocConsumer.listener` instead.
- **Using `BlocProvider.value` for a bloc the widget itself should own.** `.value` does not close
  the instance; reserve it for handing an existing bloc across a boundary (e.g. into a pushed
  route), and use the `create` constructor everywhere a screen should own and auto-close its own
  Cubit/Bloc.
