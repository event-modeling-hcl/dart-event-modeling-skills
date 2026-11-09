// DELIVERABLE 3 of 3 — the corrected bloc.
//
// The bug: the old handler built `ItemAddedEvent` (a domain fact) by hand
// inside the UI layer, instead of asking the domain to decide whether the
// item can be added. That skips the decider's business rules entirely and
// can desynchronize the UI from whatever the write model actually persists.
//
// The fix: translate UI intent (`AddItemRequested`) into a domain command
// (`domain.AddItemCommand`), hand it to the write-model aggregate's
// `handle()`, and translate whatever domain events come back into UI state.
// The bloc never constructs a `domain.ItemEvent` itself — only
// `itemDecider.decide` (see item_decider.dart) is allowed to do that.
//
// Note the `as domain` import prefix: every cross-layer reference reads as
// `domain.AddItemCommand`, `domain.ItemAddedEvent`, etc. That is the
// reusable rule from RESPONSE.md made visible in code — a reviewer sees
// instantly whether a given line is UI-owned or domain-owned.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'add_item_event.dart';
import 'add_item_view_state.dart';
import 'item_decider.dart' as domain;

final class AddItemBloc extends Bloc<AddItemRequested, AddItemViewState> {
  AddItemBloc({
    required domain.EventSourcingAggregate<domain.ItemCommand,
            domain.ItemState, domain.ItemEvent, dynamic, dynamic>
        itemAggregate,
  })  : _itemAggregate = itemAggregate,
        super(const AddItemInitial()) {
    on<AddItemRequested>(_onAddItemRequested);
  }

  final domain.EventSourcingAggregate<domain.ItemCommand, domain.ItemState,
      domain.ItemEvent, dynamic, dynamic> _itemAggregate;

  Future<void> _onAddItemRequested(
    AddItemRequested requested,
    Emitter<AddItemViewState> emit,
  ) async {
    emit(const AddItemInProgress());

    // UI intent -> domain command. This is the only translation the bloc
    // is allowed to perform; the domain fact itself is decided downstream.
    final command = domain.AddItemCommand(
      itemId: requested.itemId,
      name: requested.name,
    );

    final resultingEvents = await _itemAggregate.handle(command).toList();

    emit(_viewStateFor(resultingEvents));
  }

  AddItemViewState _viewStateFor(List<domain.ItemEvent> events) {
    for (final event in events) {
      switch (event) {
        case domain.ItemAddedEvent(:final itemId):
          return AddItemSuccess(itemId: itemId);
        case domain.ItemAdditionRejectedEvent(:final reason):
          return AddItemFailure(message: reason);
        case domain.ItemRemovedEvent():
          break; // Not a possible outcome of AddItemCommand; ignored.
      }
    }
    return const AddItemFailure(message: 'No response from the domain.');
  }
}
