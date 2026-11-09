/// Composition root for the transfer-money feature.
///
/// Wires the fmodel-dart write model (decider + event repository +
/// aggregate) into the application service, and the service into
/// [TransferBloc]. Nothing here is Bloc- or fmodel-internal — it's the glue
/// a DI container (get_it, riverpod, whatever you use) or a plain factory
/// function would own in a real app.
library;

import 'package:bloc/bloc.dart';
import 'package:fmodel/application.dart' show EventRepository, NoMetadata;

import 'transfer_bloc.dart';
import 'transfer_money_domain.dart';
import 'transfer_money_service.dart';
import 'transfer_ui_event.dart';
import 'transfer_ui_state.dart';

/// Builds a ready-to-use [TransferBloc] with a concrete write-model stack
/// underneath it.
///
/// [eventRepository] defaults to an in-memory stand-in so this file runs
/// standalone; pass your real event-store-backed repository in production.
TransferBloc buildTransferBloc({
  EventRepository<TransferMoneyCommand, LedgerEvent, NoMetadata, NoMetadata>?
  eventRepository,
}) {
  final repository = eventRepository ?? InMemoryTransferEventRepository();
  final aggregate = buildTransferMoneyAggregate(eventRepository: repository);
  final service = TransferMoneyService(transferMoneyAggregate: aggregate);

  return TransferBloc(transferMoneyService: service);
}

/// App-wide audit trail of every UI event any Bloc receives and every state
/// transition it makes.
///
/// This is the idiomatic bloc-library answer to "I want an auditable stream
/// of what the user did": install one `BlocObserver` at app startup
/// (`Bloc.observer = AuditingBlocObserver()`) instead of hand-rolling
/// logging inside each Bloc. [onEvent] fires for every `TransferUiEvent`
/// (and every other Bloc's events, if you use this observer app-wide) in
/// the exact order it was added — never for `LedgerEvent`s, which live
/// entirely on the write-model side and never pass through a Bloc at all.
class AuditingBlocObserver extends BlocObserver {
  const AuditingBlocObserver();

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (event is TransferUiEvent) {
      // Replace with your real audit sink (structured logger, analytics,
      // an actual append-only audit log table, ...).
      // ignore: avoid_print
      print('[audit] ${bloc.runtimeType} received $event');
    }
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    if (bloc is TransferBloc) {
      final next = transition.nextState as TransferUiState;
      // ignore: avoid_print
      print('[audit] TransferBloc -> ${next.status}');
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[audit] ${bloc.runtimeType} error: $error');
    super.onError(bloc, error, stackTrace);
  }
}

/// Example composition, e.g. called once from `main()` before `runApp`:
///
/// ```dart
/// void main() {
///   Bloc.observer = const AuditingBlocObserver();
///   runApp(MyApp());
/// }
/// ```
///
/// and then, in the widget tree:
///
/// ```dart
/// BlocProvider(
///   create: (_) => buildTransferBloc(eventRepository: myRealEventRepository),
///   child: const TransferScreen(),
/// )
/// ```
///
/// A submit button then does nothing more than:
///
/// ```dart
/// context.read<TransferBloc>().add(
///   TransferSubmitted(
///     fromAccountId: fromAccountId,
///     toAccountId: toAccountId,
///     amountMinorUnits: amountMinorUnits,
///     currency: currency,
///   ),
/// );
/// ```
///
/// Rapid double-taps just enqueue two `TransferSubmitted` UI events;
/// `sequential()` (registered in `transfer_bloc.dart`) is what guarantees
/// they hit the aggregate one at a time.
const transferFeatureWiringExample = true;
