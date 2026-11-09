// lib/presentation/add_item/add_item_ui_state.dart
part of 'add_item_cubit.dart';

/// Lifecycle of the Add Item screen.
///
/// `initial` is pre-fetch; `loading` covers both the first
/// `loadWardrobe()` call and every subsequent `addItem()` call;
/// `success`/`failure` describe the outcome of the most recently completed
/// operation. Named `AddItemStatus`, not `AddItemState` — the enum
/// describing "what phase is this UI in" is not the same concept as the
/// domain's `AddItemState` (the Decider's folded write-model), and reusing
/// that name here would recreate exactly the ambiguity this skill removes.
enum AddItemStatus { initial, loading, success, failure }

/// What the Add Item screen renders.
///
/// Naming note: this is `AddItemUiState`, never a bare `AddItemState`. The
/// domain layer already owns `AddItemState` for the Decider's write-model
/// (`lib/state_change/add_item/api.dart`) — a completely different shape
/// with a completely different lifetime (it only exists transiently while
/// folding events to run `decide`; it is never held anywhere for a UI to
/// read). Adding the `Ui` marker on this side, instead of renaming the
/// domain type, is the fix the fmodel_bloc skill prescribes for the "Bloc
/// State vs Aggregate/Decider State" collision.
///
/// A [Cubit]'s `emit` de-dupes consecutive equal states by `==`, so this
/// class extends [Equatable] with every field listed in `props` — leaving
/// one out would either break de-duping silently, or make two visually
/// different states compare equal.
final class AddItemUiState extends Equatable {
  const AddItemUiState({
    this.status = AddItemStatus.initial,
    this.wardrobe,
    this.error,
  });

  const AddItemUiState.initial() : this();

  final AddItemStatus status;

  /// The READ-side projection (`WardrobeViewState` from
  /// `lib/state_view/wardrobe_view/api.dart`), never the write-side
  /// `AddItemState`. This is the one field that makes the CQRS boundary
  /// real in code: `AddItemCubit` can only ever populate this by calling
  /// `WardrobeService.wardrobe()` (the query side), never by reading back
  /// what `addItemDecider` folded.
  final WardrobeViewState? wardrobe;

  /// The rejected-command / fetch-failure message, set on
  /// `AddItemStatus.failure`. Left un-defaulted in `copyWith` (rather than
  /// `error ?? this.error`) so a successful transition can explicitly
  /// clear a previous failure by passing `error: null`.
  final String? error;

  /// Convenience for widgets: true while either the initial fetch or an
  /// `addItem` call is in flight.
  bool get isSubmitting => status == AddItemStatus.loading;

  AddItemUiState copyWith({
    AddItemStatus? status,
    WardrobeViewState? wardrobe,
    String? error,
  }) => AddItemUiState(
    status: status ?? this.status,
    // Keep the last known-good projection instead of losing it on every
    // transition — a rejected `addItem` call should not blank a list the
    // user was already looking at.
    wardrobe: wardrobe ?? this.wardrobe,
    error: error,
  );

  @override
  List<Object?> get props => [status, wardrobe, error];
}
