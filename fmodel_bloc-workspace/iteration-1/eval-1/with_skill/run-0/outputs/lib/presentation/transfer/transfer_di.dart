import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/account_service.dart';
import '../../domain/account_view_api.dart';
import 'transfer_bloc.dart';

/// Dependency injection and widget wiring for the Transfer Money screen.
///
/// `AccountService` is injected via `RepositoryProvider` (a plain
/// collaborator, not itself a Bloc/Cubit); `TransferBloc` is created from
/// it via `BlocProvider`, which also takes care of closing the Bloc when
/// the screen is popped. Neither the widget tree nor `TransferBloc` itself
/// ever constructs an `EventSourcingAggregate` or a repository directly —
/// see NAMING-AND-LAYERS.md, section 5.
class TransferPage extends StatelessWidget {
  const TransferPage({
    super.key,
    required this.accountService,
    required this.accountId,
  });

  /// Constructed once, above this screen (e.g. in `main.dart` or a parent
  /// route) and handed down — this widget does not build it itself.
  final AccountService accountService;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<AccountService>.value(
      value: accountService,
      child: BlocProvider<TransferBloc>(
        create: (ctx) =>
            TransferBloc(ctx.read<AccountService>(), accountId: accountId)
              ..add(const AccountOverviewRequested()),
        child: const _TransferView(),
      ),
    );
  }
}

class _TransferView extends StatelessWidget {
  const _TransferView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer money')),
      body: BlocConsumer<TransferBloc, TransferUiState>(
        listenWhen: (previous, current) =>
            current.status == TransferStatus.failure,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error ?? 'Transfer failed.')),
          );
        },
        buildWhen: (previous, current) => previous.status != current.status,
        builder: (context, state) {
          return switch (state.status) {
            TransferStatus.initial || TransferStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            TransferStatus.success ||
            TransferStatus.failure => _TransferForm(account: state.account),
          };
        },
      ),
    );
  }
}

class _TransferForm extends StatefulWidget {
  const _TransferForm({required this.account});

  final AccountViewState? account;

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final _toAccountController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _toAccountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _toAccountController,
            decoration: const InputDecoration(labelText: 'To account'),
          ),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (cents)'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            // A button never builds a TransferMoneyCommand itself — only
            // this TransferUiEvent. context.read (not watch) is correct
            // inside a callback: we want the instance, not a rebuild
            // subscription.
            onPressed: widget.account == null
                ? null
                : () {
                    final amountCents =
                        int.tryParse(_amountController.text) ?? 0;
                    context.read<TransferBloc>().add(
                      TransferSubmitted(
                        fromAccountId: widget.account!.accountId,
                        toAccountId: _toAccountController.text,
                        amountCents: amountCents,
                      ),
                    );
                  },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

/// Presentation-layer audit log: every dispatched [TransferUiEvent] is a
/// discrete, typed fact about what the user asked for. Register this once,
/// e.g. in `main()` with `Bloc.observer = TransferAuditObserver();`, to get
/// an auditable stream of user intent independent of the ledger's own
/// domain-event log — this is the other half of "why Bloc, not Cubit" from
/// the prompt, alongside `sequential()`.
class TransferAuditObserver extends BlocObserver {
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (bloc is TransferBloc && event is TransferUiEvent) {
      // Replace with your real audit sink (structured logger, analytics,
      // an append-only audit table) — never the ledger's event store; a
      // UiEvent is an intent, not a LedgerEvent fact.
      debugPrint(
        '[transfer-audit] ${DateTime.now().toIso8601String()} '
        '$event',
      );
    }
  }
}
