// lib/presentation/add_item/add_item_page.dart
//
// The widget layer: dependency injection (`RepositoryProvider` +
// `BlocProvider`) and the screen itself. Everything here imports only
// Flutter, `flutter_bloc`, and `add_item_cubit.dart` — never a domain type
// (`AddItemCommand`, `WardrobeEvent`, ...) and never `wardrobe_service.dart`
// directly outside of the injection point in [AddItemPage]. If a widget
// ever needs to import a domain type to do its job, that is a layering
// defect: the missing translation belongs in `AddItemCubit`, not here.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/wardrobe_service.dart';
import 'add_item_cubit.dart';

/// Composition point for this screen.
///
/// [service] is constructed once, above this screen — typically in
/// `main.dart` via `buildWardrobeService(...)` (see
/// `wardrobe_service.dart`) — and handed down. `AddItemPage` does not build
/// the service itself, which is what lets it (and everything below it) be
/// tested with a fake `WardrobeService` instead of a real event store.
class AddItemPage extends StatelessWidget {
  const AddItemPage({super.key, required this.service});

  final WardrobeService service;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<WardrobeService>.value(
      value: service,
      child: BlocProvider<AddItemCubit>(
        // The Cubit's only collaborator is the injected service — it never
        // constructs an aggregate, a repository, or an event store itself.
        // `..loadWardrobe()` populates the list immediately so the screen
        // does not open empty.
        create: (ctx) =>
            AddItemCubit(ctx.read<WardrobeService>())..loadWardrobe(),
        child: const _AddItemView(),
      ),
    );
  }
}

class _AddItemView extends StatelessWidget {
  const _AddItemView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wardrobe')),
      body: BlocConsumer<AddItemCubit, AddItemUiState>(
        // Side effects (a SnackBar) belong in `listener`, not `builder` —
        // a builder reruns on every rebuild, not just the transition that
        // triggered the failure.
        listenWhen: (previous, current) =>
            current.status == AddItemStatus.failure &&
            current.error != previous.error,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error ?? 'Could not add item')),
          );
        },
        builder: (context, state) {
          final items = state.wardrobe?.items ?? const [];
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: _AddItemForm()),
              if (state.status == AddItemStatus.failure)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    state.error ?? 'Could not add item',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: state.status == AddItemStatus.initial
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                    ? const Center(
                        child: Text('No items yet — add your first one above.'),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(item.category),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The name/category form and the "Add" button. A `StatefulWidget` only to
/// own and dispose its `TextEditingController`s — it holds no business
/// state of its own; `AddItemCubit` is the single source of truth for
/// whether a submission is in flight.
class _AddItemForm extends StatefulWidget {
  const _AddItemForm();

  @override
  State<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends State<_AddItemForm> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when submitting-ness actually changes, so typing in the
    // fields does not thrash this widget on every keystroke.
    final isSubmitting = context.select<AddItemCubit, bool>(
      (cubit) => cubit.state.isSubmitting,
    );

    return Column(
      children: [
        TextField(
          controller: _nameController,
          enabled: !isSubmitting,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _categoryController,
          enabled: !isSubmitting,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          // `context.read`, not `context.watch`: this is a one-shot
          // callback, not part of `build`, so it should not register a
          // rebuild subscription.
          onPressed: isSubmitting
              ? null
              : () {
                  // The widget hands over raw form strings; it never
                  // constructs an `AddItemCommand` itself — that
                  // translation belongs to `AddItemCubit.addItem`.
                  context.read<AddItemCubit>().addItem(
                    name: _nameController.text,
                    category: _categoryController.text,
                  );
                },
          child: isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
