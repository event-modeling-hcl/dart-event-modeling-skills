import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

// Domain + application types, owned by the fmodel decider/view layer.
// Imported, never redefined and never renamed — see RESPONSE.md §2.
//
//   AddItemCommand    : the intent handed to the decider's `decide()`.
//   DomainError        : sealed base of the decider's rejection reasons.
//   WardrobeViewState  : the read-model projection folded by the `View`.
//
// Deliberately NOT imported here: `ItemAddedEvent` (the domain event the
// decider emits) and the decider's write-model `AddItemState`. Neither
// belongs in the presentation layer — see the bug this file fixes below.
import '../../state_change/add_item/api.dart'; // AddItemCommand, DomainError
import '../../state_view/wardrobe_view/api.dart'; // WardrobeViewState
import '../../application/wardrobe_service.dart'; // WardrobeService

part 'add_item_ui_event.dart';
part 'add_item_ui_state.dart';

/// Presentation-layer bloc for the Add Item screen.
///
/// Fixes the bug where the previous `AddItemEvent` handler constructed the
/// domain's `ItemAddedEvent` directly, bypassing the decider's business
/// rules. This bloc never touches `ItemAddedEvent` or the decider's
/// write-model `AddItemState` — it only ever:
///
/// 1. receives a [AddItemUiEvent] (a UI intent),
/// 2. builds an [AddItemCommand] from it,
/// 3. hands the command to the application service, which runs the
///    decider's `decide -> evolve -> persist` cycle and produces
///    `ItemAddedEvent`(s) internally,
/// 4. reads the fresh [WardrobeViewState] projection back from the read
///    side, and
/// 5. emits a new [AddItemUiState] built from that projection.
class AddItemBloc extends Bloc<AddItemUiEvent, AddItemUiState> {
  AddItemBloc(this._service) : super(const AddItemUiState.initial()) {
    // `sequential()` serializes command handling so two concurrent submits
    // can never race the same aggregate's fetch -> decide -> save cycle.
    on<AddItemSubmitted>(_onAddItemSubmitted, transformer: sequential());
    // `restartable()` is safe for a pure read: only the latest request's
    // result reaches emit, and a stale one is simply discarded.
    on<WardrobeRequested>(_onWardrobeRequested, transformer: restartable());
  }

  final WardrobeService _service;

  Future<void> _onAddItemSubmitted(
    AddItemSubmitted event,
    Emitter<AddItemUiState> emit,
  ) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      // Steps 1-2: UI intent -> fmodel Command. This is the corrected line:
      // build AddItemCommand, never construct ItemAddedEvent here. Only the
      // decider's decide() is allowed to produce that domain event.
      final command = AddItemCommand(name: event.name, category: event.category);

      // Step 3: application layer runs decide -> evolve -> persist and
      // returns/streams the resulting domain events internally.
      await _service.handle(command);

      // Step 4: read fresh render data from the read side (the View
      // projection), never from the decider's write-model AddItemState.
      final wardrobe = await _service.wardrobe();

      // Step 5: emit a UiState built from the read model.
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: wardrobe));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }

  Future<void> _onWardrobeRequested(
    WardrobeRequested event,
    Emitter<AddItemUiState> emit,
  ) async {
    emit(state.copyWith(status: AddItemStatus.loading));
    try {
      final wardrobe = await _service.wardrobe();
      emit(state.copyWith(status: AddItemStatus.success, wardrobe: wardrobe));
    } on DomainError catch (e) {
      emit(state.copyWith(status: AddItemStatus.failure, error: e.message));
    }
  }
}
