// lib/application/wardrobe_service.dart
//
// Application layer. This is the ONE collaborator `AddItemCubit` depends
// on (see add_item_cubit.dart) — the Cubit never imports `package:fmodel`,
// never touches `addItemDecider`/`wardrobeView` directly, and never sees a
// repository port. Everything fmodel-shaped funnels through this file.
import 'package:fmodel/fmodel.dart';

import '../state_change/add_item/api.dart'
    show AddItemCommand, AddItemState, addItemDecider;
// `WardrobeEvent` is the shared domain-event base both `addItemDecider`
// and `wardrobeView` fold over — it is a bounded-context type, re-exported
// here via the wardrobe-view slice's `api.dart`. If your project instead
// exports it from a `bounded_contexts/wardrobe/api.dart` (the layout the
// upstream `map-event-model-hcl-to-code` skill defaults to), import it
// from there instead; nothing else in this file changes.
import '../state_view/wardrobe_view/api.dart'
    show WardrobeViewState, WardrobeEvent;

/// Reads the current wardrobe projection.
///
/// This is deliberately a function, not a named repository class: your
/// `wardrobeView` is already wired into a `MaterializedView` via
/// `createMaterializedView(view: wardrobeView, viewStateRepository: ...)`,
/// and something in your platform layer (an event-store subscription or
/// projector) already calls `.handle(event)` on it for every new
/// `WardrobeEvent` to keep that projection's backing store up to date.
/// `MaterializedView.handle` is shaped to fold *one event* into the
/// projection, though — it is not a "just give me the current state" read.
/// A `WardrobeReader` is the seam for that read: wrap whatever query your
/// concrete `ViewStateRepository` adapter already exposes (a Drift/Hive/SQL
/// lookup, an in-memory map read, etc.) in a zero-argument function of this
/// shape, and hand it to [WardrobeService]. Neither the Cubit nor this
/// service needs to know which storage backs it.
typedef WardrobeReader = Future<WardrobeViewState> Function();

/// The single application-layer façade `AddItemCubit` is built against.
///
/// It wraps exactly two things: the write-side `EventSourcingAggregate`
/// (built from `addItemDecider`) and a read-side [WardrobeReader] backed by
/// the wardrobe `MaterializedView`'s projection store. The Cubit calls
/// [addItem] then [wardrobe] — it never knows, or needs to know, that an
/// aggregate and a materialized view sit behind those two calls.
class WardrobeService {
  WardrobeService({
    required EventSourcingAggregate<
      AddItemCommand,
      AddItemState,
      WardrobeEvent,
      NoMetadata,
      NoMetadata
    >
    addItemAggregate,
    required WardrobeReader wardrobeReader,
  }) : _addItemAggregate = addItemAggregate,
       _wardrobeReader = wardrobeReader;

  final EventSourcingAggregate<
    AddItemCommand,
    AddItemState,
    WardrobeEvent,
    NoMetadata,
    NoMetadata
  >
  _addItemAggregate;
  final WardrobeReader _wardrobeReader;

  /// Step 3 of the seam: runs the write side. `EventSourcingAggregate.handle`
  /// returns a `Stream<WardrobeEvent>` of the newly persisted domain
  /// events (here, `ItemAddedEvent`); `.drain<void>()` consumes the stream
  /// so persistence completes before this future resolves. If
  /// `addItemDecider.decide` rejects the command, the `DomainError` it
  /// throws propagates out of this call — `WardrobeService` does not catch
  /// it, `AddItemCubit` does.
  Future<void> addItem(AddItemCommand command) =>
      _addItemAggregate.handle(command).drain<void>();

  /// Step 4 of the seam: reads the current READ-side projection. Never
  /// built from `_addItemAggregate`'s write-side state — that would break
  /// the CQRS boundary the fmodel_bloc skill enforces.
  Future<WardrobeViewState> wardrobe() => _wardrobeReader();
}

/// Composition-root helper: wires the already-existing `addItemDecider`
/// into fmodel's application-layer object using the library's own
/// `createEventSourcingAggregate` factory. Call this once — e.g. from
/// `main.dart` or a dependency-injection module — and hand the resulting
/// [WardrobeService] down through `RepositoryProvider` (see
/// `add_item_page.dart`).
///
/// [addItemEventRepository] is the `EventRepository` adapter over your
/// event store for this command (an `EventRepository<AddItemCommand,
/// WardrobeEvent, NoMetadata, NoMetadata>` — already produced alongside
/// `addItemDecider` by the domain/application layer). [wardrobeReader]
/// wraps the read query described on [WardrobeReader] above. This function
/// only composes existing pieces; it does not build the `MaterializedView`
/// or its projector — those already exist per this task's brief, and stay
/// wired wherever your event subscription lives.
WardrobeService buildWardrobeService({
  required EventRepository<
    AddItemCommand,
    WardrobeEvent,
    NoMetadata,
    NoMetadata
  >
  addItemEventRepository,
  required WardrobeReader wardrobeReader,
}) {
  final addItemAggregate = createEventSourcingAggregate(
    decider: addItemDecider,
    eventRepository: addItemEventRepository,
  );

  return WardrobeService(
    addItemAggregate: addItemAggregate,
    wardrobeReader: wardrobeReader,
  );
}
