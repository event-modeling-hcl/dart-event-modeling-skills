// lib/presentation/add_item/add_item_cubit.dart
//
// Presentation layer. Owns the ONLY translation from a UI intent (a typed
// name + category and a tap on "Add") into the domain's `AddItemCommand`,
// and the only place a fresh `WardrobeViewState` projection is turned into
// render data for the screen.
//
// Naming discipline (see the fmodel_bloc skill's NAMING-AND-LAYERS.md):
//   - Domain types (`AddItemCommand`, `AddItemState`, `DomainError`,
//     `WardrobeViewState`, `WardrobeEvent`, `ItemAddedEvent`) keep the
//     names the domain layer already gave them. They are imported below,
//     never redefined.
//   - Every presentation type here carries the `Ui` marker
//     (`AddItemUiState`, `AddItemStatus`) so nobody can mistake this
//     Cubit's state for the Decider's write-model state of the same
//     feature.
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Domain layer, owned by fmodel / the upstream `map-event-model-hcl-to-code`
// generator. Imported, never redefined or renamed.
import '../../state_change/add_item/api.dart' show AddItemCommand, DomainError;
import '../../state_view/wardrobe_view/api.dart' show WardrobeViewState;

// Application layer: the Cubit's single collaborator. See
// `wardrobe_service.dart` for what it wraps and how it is composed from
// fmodel's `create...` factories.
import '../../application/wardrobe_service.dart';

part 'add_item_ui_state.dart';

/// State management for the "add item to wardrobe" screen.
///
/// This is a [Cubit], not a `Bloc`: the screen has exactly one UI intent
/// ("tap Add with this name/category") that maps 1:1 onto one domain
/// command (`AddItemCommand`). A public method call *is* the command
/// dispatch, so there is no `AddItemUiEvent` type to define — which means
/// the "Bloc Event vs Domain Event" collision the fmodel_bloc skill exists
/// to prevent cannot arise in this file at all. If a second, ordering- or
/// debounce-sensitive intent shows up on this screen later, promote to an
/// `AddItemBloc` (see the skill's BLOC-INTEGRATION.md); until then, a
/// Cubit is the simpler, equally valid choice.
class AddItemCubit extends Cubit<AddItemUiState> {
  AddItemCubit(this._service) : super(const AddItemUiState.initial());

  /// The Cubit's ONE collaborator, constructor-injected — never built here.
  /// It is what stands between this file and fmodel's `Decider`/`View`
  /// machinery; the Cubit never touches an aggregate, a view, or a
  /// repository directly, which is what keeps it testable with a fake
  /// `WardrobeService` in `add_item_cubit_test.dart`.
  final WardrobeService _service;

  /// Loads the current wardrobe projection without running any command.
  /// Call this once when the screen is created (see `add_item_page.dart`,
  /// `AddItemCubit(...)..loadWardrobe()`) so the list is populated before
  /// the user adds anything.
  Future<void> loadWardrobe() async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      final wardrobe = await _service.wardrobe();
      emit(
        state.copyWith(
          status: AddItemStatus.success,
          wardrobe: wardrobe,
          error: null,
        ),
      );
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  /// One UI intent, one domain command — the five-step seam from the
  /// fmodel_bloc skill, spelled out step by step:
  Future<void> addItem({required String name, required String category}) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      // 1-2: UI intent -> domain Command. This Cubit is the only place
      // allowed to construct an `AddItemCommand` — the widget layer only
      // ever hands it raw strings from the form.
      final command = AddItemCommand(name: name, category: category);

      // 3: application layer runs `addItemDecider.decide`, persists the
      // resulting `ItemAddedEvent`, and can reject the command by throwing
      // a `DomainError` — none of that is this file's concern.
      await _service.addItem(command);

      // 4: read fresh render data from the READ side (`WardrobeViewState`
      // via the view/materialized-view projection), never from the
      // write-side `AddItemState` the decider folds. This is what makes
      // "Bloc State != Aggregate State" true in code, not just in
      // principle.
      final wardrobe = await _service.wardrobe();

      // 5: emit a UiState carrying that projection plus a status.
      emit(
        state.copyWith(
          status: AddItemStatus.success,
          wardrobe: wardrobe,
          error: null,
        ),
      );
    } on DomainError catch (e) {
      // A rejected command (e.g. a duplicate item, an invalid category) is
      // a *DomainError*, not a bug — map it to `failure` and keep the last
      // known-good `wardrobe` projection (see `copyWith` in
      // add_item_ui_state.dart) instead of blanking the list the user is
      // looking at. Catching `DomainError` specifically, rather than
      // `Object`/`Exception`, means a real bug (a null-check failure, a
      // repository timeout) still surfaces instead of being reported to
      // the user as a rejected command.
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }
}
