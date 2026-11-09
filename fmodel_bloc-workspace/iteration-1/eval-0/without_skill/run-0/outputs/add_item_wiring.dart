// Suggested location in the app: lib/features/add_item/view/add_item_wiring.dart
// (or wherever your app composes its top-level dependency graph, e.g. a
// service locator module).
//
// Shows how to go from the fmodel primitives you already have (the
// `addItemDecider` Decider, the `wardrobeView` View, and repositories for
// each) down to a widget-ready `AddItemCubit`, without the Cubit ever
// knowing fmodel exists.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fmodel/application.dart';

import 'package:wardrobe/state_change/add_item/api.dart';
import 'package:wardrobe/state_change/add_item/application/add_item_service.dart';
import 'package:wardrobe/state_view/wardrobe_view/api.dart';

import 'cubit/add_item_cubit.dart';
import 'view/add_item_screen.dart';

/// Builds the fully-wired add-item screen.
///
/// `eventRepository` and `viewStateRepository` are whatever storage-backed
/// implementations your app already uses for events and projected view
/// state (in-memory, SQLite, a backend API, etc.) - they are not part of
/// this task, only their types are needed here.
Widget buildAddItemScreen({
  required EventRepository<
    AddItemCommand,
    WardrobeEvent,
    NoMetadata,
    NoMetadata
  >
  eventRepository,
  required ViewStateRepository<WardrobeEvent, WardrobeViewState, NoMetadata>
  viewStateRepository,
}) {
  // 1. Build the fmodel application-layer primitives from your existing
  //    domain decider/view via the `create...` factories, exactly as you
  //    already do elsewhere in the app.
  final aggregate = createEventSourcingAggregate(
    decider: addItemDecider,
    eventRepository: eventRepository,
  );

  final materializedView = createMaterializedView(
    view: wardrobeView,
    viewStateRepository: viewStateRepository,
  );

  // 2. Wrap both in the application service the Cubit depends on.
  final addItemService = AddItemService(
    aggregate: aggregate,
    materializedView: materializedView,
  );

  // 3. Inject the service into the Cubit via its constructor (never
  //    constructed inside the Cubit itself), and provide the Cubit to the
  //    widget subtree.
  return BlocProvider<AddItemCubit>(
    create: (_) => AddItemCubit(addItemService: addItemService),
    child: const AddItemScreen(),
  );
}
