// Suggested location in the app: lib/features/add_item/cubit/add_item_ui_state.dart
//
// Presentation-only state for the add-item screen. Named `AddItemUiState`
// (note the `Ui`) on purpose: the domain already owns a type called
// `AddItemState` (the Decider's write-model state in
// lib/state_change/add_item/api.dart). Reusing that name here would make it
// ambiguous, at a glance, whether a given `AddItemState` came from the
// domain or from the screen. This type never appears in the domain layer,
// and the domain's `AddItemState` never appears here.

import 'package:equatable/equatable.dart';

// Only the read-model item type is used for rendering - the write-model
// state is never touched by the UI.
import 'package:wardrobe/state_view/wardrobe_view/api.dart' show WardrobeItem;

/// Lifecycle of the add-item use case, as seen by the screen.
enum AddItemStatus {
  /// Nothing has happened yet; showing whatever items were last loaded.
  initial,

  /// `AddItemCubit.addItem` is in flight.
  loading,

  /// The last add-item attempt succeeded; `items` reflects the latest
  /// read-model projection.
  success,

  /// The last add-item attempt failed, either because the domain rejected
  /// it or because of a local validation issue; `errorMessage` explains why.
  failure,
}

/// Immutable UI state for the add-item screen.
///
/// `items` always comes from the read-model projection
/// (`WardrobeViewState.items`, exposed via [WardrobeItem]) returned by the
/// application service after a command is handled - never from the
/// Decider/aggregate's write-model state.
final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.items = const <WardrobeItem>[],
    this.errorMessage,
  });

  final AddItemStatus status;
  final List<WardrobeItem> items;
  final String? errorMessage;

  bool get isLoading => status == AddItemStatus.loading;
  bool get hasError => status == AddItemStatus.failure;

  AddItemUiState copyWith({
    AddItemStatus? status,
    List<WardrobeItem>? items,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AddItemUiState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, items, errorMessage];
}
