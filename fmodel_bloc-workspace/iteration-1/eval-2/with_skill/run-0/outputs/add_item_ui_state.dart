part of 'add_item_bloc.dart';

/// Status of the Add Item screen's last requested operation.
enum AddItemStatus { initial, loading, success, failure }

/// What the Add Item screen renders.
///
/// This is the renamed replacement for the old bare `AddItemState` in the
/// bloc file. It is built entirely from the **read side** — the
/// [WardrobeViewState] projection maintained by the `View` — plus a status
/// flag for the in-flight/success/failure UI. It never embeds or is built
/// from the decider's write-model `AddItemState`; that type is internal to
/// the aggregate and the UI has no business reading it.
///
/// Extends [Equatable] because `Bloc.emit` de-dupes consecutive states by
/// `==`; without value equality, two structurally identical states would
/// still compare unequal and the widget tree would rebuild needlessly.
final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.wardrobe,
    this.error,
  });

  const AddItemUiState.initial() : this();

  /// Status of the last submitted intent (add / refresh / search).
  final AddItemStatus status;

  /// Read-model projection the screen renders. Sourced from the `View`,
  /// never from the decider's write-model state.
  final WardrobeViewState? wardrobe;

  /// Human-readable message when [status] is [AddItemStatus.failure].
  final String? error;

  AddItemUiState copyWith({
    AddItemStatus? status,
    WardrobeViewState? wardrobe,
    String? error,
  }) =>
      AddItemUiState(
        status: status ?? this.status,
        wardrobe: wardrobe ?? this.wardrobe,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, wardrobe, error];
}
