// Suggested location in the app: lib/state_change/add_item/application/add_item_service.dart
//
// Thin application-layer service that composes the already-existing
// `EventSourcingAggregate` (write side) and `MaterializedView` (read side)
// into a single use case: "add an item and hand back the freshest read
// model". This is the one object the presentation layer (the Cubit) talks
// to - it never sees the Decider or the View directly.
//
// Deliberately NOT a domain type: it only orchestrates calls into
// `AddItemCommand`, `WardrobeEvent`, `AddItemState` and `WardrobeViewState`,
// all of which are imported, never redefined here.

import 'package:fmodel/application.dart';

// Adjust these two imports to your package name (see pubspec.yaml `name:`).
import 'package:wardrobe/state_change/add_item/api.dart';
import 'package:wardrobe/state_view/wardrobe_view/api.dart';

/// Application service backing the "add item" screen.
///
/// Wraps the write-side [EventSourcingAggregate] (built with
/// `createEventSourcingAggregate(decider: addItemDecider, ...)`) and the
/// read-side [MaterializedView] (built with `createMaterializedView(view:
/// wardrobeView, ...)`) so the presentation layer only has to call one
/// method and never has to know how events get from one side to the other.
final class AddItemService {
  const AddItemService({
    required EventSourcingAggregate<
      AddItemCommand,
      AddItemState,
      WardrobeEvent,
      NoMetadata,
      NoMetadata
    >
    aggregate,
    required MaterializedView<WardrobeViewState, WardrobeEvent, NoMetadata>
    materializedView,
  }) : _aggregate = aggregate,
       _materializedView = materializedView;

  final EventSourcingAggregate<
    AddItemCommand,
    AddItemState,
    WardrobeEvent,
    NoMetadata,
    NoMetadata
  >
  _aggregate;
  final MaterializedView<WardrobeViewState, WardrobeEvent, NoMetadata>
  _materializedView;

  /// Runs [command] through the write-side aggregate, projects every
  /// resulting event through the read-side materialized view, and returns
  /// the freshest [WardrobeViewState] once the whole event stream has been
  /// applied.
  ///
  /// If the domain rejects the command, `_aggregate.handle` throws (or
  /// yields a stream error) before any event is produced, and that error
  /// propagates unchanged to the caller - it is the Cubit's job to turn it
  /// into a UI-facing failure state, not this service's.
  Future<WardrobeViewState> addItem(AddItemCommand command) async {
    WardrobeViewState? latestViewState;

    await for (final event in _aggregate.handle(command)) {
      latestViewState = await _materializedView.handle(event);
    }

    if (latestViewState == null) {
      // The decider accepted the command but produced no events - treat it
      // as a no-op rather than silently losing the update.
      throw StateError(
        'AddItemCommand($command) produced no events; nothing to project.',
      );
    }

    return latestViewState;
  }
}
