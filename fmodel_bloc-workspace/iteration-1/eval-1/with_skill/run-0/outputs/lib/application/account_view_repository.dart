/// Query-side port for fetching an [AccountViewState] by account id.
///
/// ---------------------------------------------------------------------
/// NOT PART OF THIS SKILL'S DELIVERABLE — application-layer port owned by
/// fmodel / the upstream skill, shown only so `AccountService`
/// (`account_service.dart`, which *is* this skill's deliverable) has
/// something concrete to depend on. A real implementation adapts fmodel's
/// `ViewStateRepository`/`MaterializedView` machinery to "fetch the latest
/// projection for this account id"; that wiring belongs upstream, not here.
/// ---------------------------------------------------------------------
library;

import '../domain/account_view_api.dart';

abstract interface class AccountViewRepository {
  /// Returns the current read-model projection for [accountId].
  Future<AccountViewState> fetchByAccountId(String accountId);
}
