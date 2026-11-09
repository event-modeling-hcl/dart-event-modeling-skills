part of 'add_item_bloc.dart';

/// UI intents for the Add Item screen.
///
/// This is a bloc **event** hierarchy, which is *not* a domain event
/// hierarchy. Each case here expresses something the user (or the widget
/// tree) is asking for; it maps to an fmodel [AddItemCommand] (or a query)
/// inside [AddItemBloc]. None of these cases is, wraps, or extends the
/// domain's `ItemAddedEvent` — that type belongs to the decider's
/// `WardrobeEvent` hierarchy and is produced only by `decide()`.
sealed class AddItemUiEvent extends Equatable {
  const AddItemUiEvent();

  @override
  List<Object?> get props => [];
}

/// The user tapped "Add" with a name and category filled in.
///
/// This is the renamed replacement for the old bare `AddItemEvent`. It
/// carries only the raw input needed to build an [AddItemCommand]; it is
/// *never* turned into `ItemAddedEvent` directly by the bloc — only the
/// decider, after validating the resulting command, may produce that fact.
final class AddItemSubmitted extends AddItemUiEvent {
  const AddItemSubmitted({required this.name, required this.category});

  final String name;
  final String category;

  @override
  List<Object?> get props => [name, category];
}

/// The screen wants the current wardrobe projection (initial load or
/// pull-to-refresh). Maps to a read-side query, not a command.
final class WardrobeRequested extends AddItemUiEvent {
  const WardrobeRequested();
}
