// DELIVERABLE 2 of 3 — the bloc's (UI) state.
//
// Renamed from `AddItemState` to `AddItemViewState`.
//
// This is what the "Add Item" screen renders: a status projection over the
// outcome of handling one `AddItemCommand`. It has no relationship to
// `ItemState` (the decider's write-model fold state, in item_decider.dart)
// beyond being derived from the domain events that state's decider emits.
library;

import 'package:equatable/equatable.dart';

sealed class AddItemViewState extends Equatable {
  const AddItemViewState();

  @override
  List<Object?> get props => [];
}

/// The form has not been submitted yet.
final class AddItemInitial extends AddItemViewState {
  const AddItemInitial();
}

/// The command is in flight — waiting on `handle()` to resolve.
final class AddItemInProgress extends AddItemViewState {
  const AddItemInProgress();
}

/// The domain accepted the command and emitted `ItemAddedEvent`.
final class AddItemSuccess extends AddItemViewState {
  const AddItemSuccess({required this.itemId});

  final String itemId;

  @override
  List<Object?> get props => [itemId];
}

/// The domain rejected the command (business rule) or handling failed.
final class AddItemFailure extends AddItemViewState {
  const AddItemFailure({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
