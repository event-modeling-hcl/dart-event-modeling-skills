// SUPPORTING CONTEXT FILE — not one of the three requested deliverables.
//
// This is the *domain* (write-model) layer: the fmodel `Decider` for the
// `Item` aggregate. It is included only so the corrected bloc file below
// compiles and reads realistically end to end. It also shows the one rename
// that belongs on this side of the boundary: the decider's fold state is
// renamed from `AddItemState` to `ItemState` (see RESPONSE.md, rename #2).
//
// Everything else here — `AddItemCommand`, `ItemAddedEvent` — is already
// named correctly for its layer and is included unchanged.
library;

import 'package:fmodel/domain.dart';

// Re-exported so callers can reach `EventSourcingAggregate` through this
// same `domain.` prefix instead of importing fmodel's application layer
// separately — the bloc only ever needs one domain-side import.
export 'package:fmodel/application.dart' show EventSourcingAggregate;

/// ---------------------------------------------------------------------
/// Commands — intent to change the Item aggregate. Input to `decide`.
/// Named `<Verb><Aggregate>Command`.
/// ---------------------------------------------------------------------
sealed class ItemCommand {
  const ItemCommand();
}

final class AddItemCommand extends ItemCommand {
  const AddItemCommand({required this.itemId, required this.name});

  final String itemId;
  final String name;
}

final class RemoveItemCommand extends ItemCommand {
  const RemoveItemCommand({required this.itemId});

  final String itemId;
}

/// ---------------------------------------------------------------------
/// Events — facts about the Item aggregate that already happened. Output
/// of `decide`, input to `evolve`. Named `<Aggregate><PastTenseVerb>Event`.
/// ---------------------------------------------------------------------
sealed class ItemEvent {
  const ItemEvent();
}

final class ItemAddedEvent extends ItemEvent {
  const ItemAddedEvent({required this.itemId, required this.name});

  final String itemId;
  final String name;
}

final class ItemAdditionRejectedEvent extends ItemEvent {
  const ItemAdditionRejectedEvent({required this.itemId, required this.reason});

  final String itemId;
  final String reason;
}

final class ItemRemovedEvent extends ItemEvent {
  const ItemRemovedEvent({required this.itemId});

  final String itemId;
}

/// ---------------------------------------------------------------------
/// State — the decider's own fold state for ONE Item aggregate instance.
///
/// Renamed from `AddItemState` to `ItemState`: this state is evolved by
/// *every* command the aggregate accepts (`AddItemCommand`,
/// `RemoveItemCommand`, and whatever comes next), not just "add". Naming
/// a decider's `S` after a single command is the modeling smell that
/// causes it to collide with a bloc state of the same name — the fix is
/// to name it after the aggregate root instead.
/// ---------------------------------------------------------------------
final class ItemState {
  const ItemState({
    required this.itemId,
    required this.name,
    required this.exists,
  });

  static const notYetCreated = ItemState(itemId: '', name: '', exists: false);

  final String itemId;
  final String name;
  final bool exists;

  ItemState copyWith({String? itemId, String? name, bool? exists}) {
    return ItemState(
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      exists: exists ?? this.exists,
    );
  }
}

/// The `Item` decider: the single place allowed to construct an `ItemEvent`.
final Decider<ItemCommand, ItemState, ItemEvent> itemDecider =
    Decider<ItemCommand, ItemState, ItemEvent>(
  initialState: ItemState.notYetCreated,
  decide: (command, state) async* {
    switch (command) {
      case AddItemCommand(:final itemId, :final name):
        if (state.exists) {
          yield ItemAdditionRejectedEvent(
            itemId: itemId,
            reason: 'Item $itemId already exists.',
          );
        } else {
          yield ItemAddedEvent(itemId: itemId, name: name);
        }
      case RemoveItemCommand(:final itemId):
        if (state.exists) {
          yield ItemRemovedEvent(itemId: itemId);
        }
    }
  },
  evolve: (state, event) => switch (event) {
    ItemAddedEvent(:final itemId, :final name) =>
      state.copyWith(itemId: itemId, name: name, exists: true),
    ItemRemovedEvent() => state.copyWith(exists: false),
    ItemAdditionRejectedEvent() => state,
  },
);
