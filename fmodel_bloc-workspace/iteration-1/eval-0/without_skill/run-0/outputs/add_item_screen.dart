// Suggested location in the app: lib/features/add_item/view/add_item_screen.dart
//
// Widget layer. It only reads `AddItemUiState` and calls
// `AddItemCubit.addItem` - it never touches fmodel types directly.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/add_item_cubit.dart';
import '../cubit/add_item_ui_state.dart';

/// Screen that lets the user type a name + category and add a wardrobe item,
/// showing the current item list, a loading spinner while the add is in
/// flight, and an error message if the domain rejects it.
///
/// Assumes an [AddItemCubit] is already available above this widget in the
/// tree (see `add_item_wiring.dart` for how to provide one).
class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _onAddPressed(BuildContext context) {
    context.read<AddItemCubit>().addItem(
      name: _nameController.text,
      category: _categoryController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add wardrobe item')),
      body: BlocConsumer<AddItemCubit, AddItemUiState>(
        listenWhen: (previous, current) =>
            current.hasError && current.errorMessage != previous.errorMessage,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'Could not add item.'),
              ),
            );
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  enabled: !state.isLoading,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  enabled: !state.isLoading,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: state.isLoading
                      ? null
                      : () => _onAddPressed(context),
                  child: state.isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
                if (state.hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage ?? 'Could not add item.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Expanded(
                  child: state.items.isEmpty
                      ? const Center(child: Text('No items yet.'))
                      : ListView.separated(
                          itemCount: state.items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = state.items[index];
                            return ListTile(
                              title: Text(item.name),
                              subtitle: Text(item.category),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
