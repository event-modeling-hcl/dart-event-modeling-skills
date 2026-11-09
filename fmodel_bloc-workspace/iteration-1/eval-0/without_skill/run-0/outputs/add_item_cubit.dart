// Suggested location in the app: lib/features/add_item/cubit/add_item_cubit.dart
//
// Method-driven Cubit for the add-item screen. A Cubit fits this use case
// better than a full Bloc: there is exactly one user gesture ("tap Add"),
// handled by exactly one method, with no need to fan external events into a
// stream of internal Bloc events first.

import 'package:bloc/bloc.dart';

// Application service lives next to the domain's write side; adjust the
// path/package name to match where you place add_item_service.dart.
import 'package:wardrobe/state_change/add_item/application/add_item_service.dart';

// Domain command type is imported, not redefined.
import 'package:wardrobe/state_change/add_item/api.dart' show AddItemCommand;

import 'add_item_ui_state.dart';

/// Drives [AddItemUiState] from user input on the add-item screen.
///
/// The [AddItemService] (which itself wraps the fmodel
/// `EventSourcingAggregate` and `MaterializedView`) is injected through the
/// constructor - the Cubit never constructs it. That keeps the Cubit
/// trivially testable with a fake/mock service and keeps fmodel wiring
/// (repositories, event/view state stores, etc.) out of the presentation
/// layer entirely.
final class AddItemCubit extends Cubit<AddItemUiState> {
  AddItemCubit({required AddItemService addItemService})
    : _addItemService = addItemService,
      super(const AddItemUiState());

  final AddItemService _addItemService;

  /// Called when the user taps "Add" with the current form values.
  ///
  /// Emits, in order: a loading state, then either a success state carrying
  /// the refreshed item list, or a failure state carrying a message - the
  /// domain rejection (or any other error thrown while handling the
  /// command) is caught here and mapped to [AddItemUiState.errorMessage]
  /// rather than being allowed to propagate up into the widget tree.
  Future<void> addItem({required String name, required String category}) async {
    final trimmedName = name.trim();
    final trimmedCategory = category.trim();

    if (trimmedName.isEmpty || trimmedCategory.isEmpty) {
      emit(
        state.copyWith(
          status: AddItemStatus.failure,
          errorMessage: 'Name and category are both required.',
        ),
      );
      return;
    }

    emit(state.copyWith(status: AddItemStatus.loading, clearError: true));

    try {
      final command = AddItemCommand(
        name: trimmedName,
        category: trimmedCategory,
      );
      final updatedView = await _addItemService.addItem(command);

      emit(
        state.copyWith(
          status: AddItemStatus.success,
          items: updatedView.items,
          clearError: true,
        ),
      );
    } catch (error) {
      // Catches whatever the domain throws/yields as a stream error when it
      // rejects the command (e.g. a validation or business-rule exception
      // raised from `addItemDecider.decide`), plus any other failure from
      // the service. Narrow this to your project's specific domain
      // exception type once you have one, for stronger typing.
      emit(
        state.copyWith(
          status: AddItemStatus.failure,
          errorMessage: _describeError(error),
        ),
      );
    }
  }

  /// Resets a failure back to [AddItemStatus.initial] without touching the
  /// currently displayed items, e.g. after the user dismisses an error
  /// banner/snackbar.
  void clearError() {
    if (state.hasError) {
      emit(state.copyWith(status: AddItemStatus.initial, clearError: true));
    }
  }

  String _describeError(Object error) {
    final message = error.toString();
    // `Exception: foo` / `StateError: foo` -> `foo`; keeps the UI message
    // free of Dart's runtime-type prefixing.
    final colonIndex = message.indexOf(': ');
    return colonIndex == -1 ? message : message.substring(colonIndex + 2);
  }
}
