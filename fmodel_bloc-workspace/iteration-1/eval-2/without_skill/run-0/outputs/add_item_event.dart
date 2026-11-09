// DELIVERABLE 1 of 3 — the bloc's (UI) event.
//
// Renamed from `AddItemEvent` to `AddItemRequested`.
//
// This is UI intent, not a domain fact: it only says "the Add Item form was
// submitted with this input." Nothing has happened yet, nothing has been
// validated yet, and no domain type is referenced here at all. It is later
// translated into a domain `AddItemCommand` inside `AddItemBloc` — see
// RESPONSE.md for why the bloc, not this class, owns that translation.
library;

import 'package:equatable/equatable.dart';

/// Fired when the user submits the "add item" form.
final class AddItemRequested extends Equatable {
  const AddItemRequested({required this.itemId, required this.name});

  final String itemId;
  final String name;

  @override
  List<Object?> get props => [itemId, name];
}
