part of 'app_providers.dart';

typedef _ModelAuthReadiness = ({
  bool authenticated,
  bool loading,
  AuthStatus status,
});

/// Rebuilds every long-lived provider that mirrors data removed by the broad
/// sign-out wipe.
void _resetProvidersAfterFullAppDataClear(Ref ref) {
  ref.read(activeConversationProvider.notifier).set(null);
  ref.invalidate(conversationsProvider);

  ref.invalidate(appSettingsProvider);
  ref.invalidate(reviewerModeProvider);
  // Theme and locale live in the app, so the host registers them rather than
  // the core reaching upward for them.
  for (final target in ref.read(signOutResetTargetsProvider)) {
    ref.invalidate(target);
  }

  ref.invalidate(openWebUiAccountSummariesProvider);
  ref.invalidate(openWebUiAccountsProvider);
  ref.read(openWebUiValidatedIdentityLedgerProvider).clear();
}

final signOutCoordinatorProvider = Provider<SignOutCoordinator>(
  SignOutCoordinator.new,
);

enum SignOutRequestResult { completed }

/// Coordinates a user-requested full local-data sign-out across the auth
/// providers. OWU-134: the app has the one seeded Open WebUI server, so the
/// sign-out always keeps its details — the next boot lands on its sign-in —
/// and the wipe only has to hold preference writes while it runs.
final class SignOutCoordinator {
  SignOutCoordinator(this._ref);

  final Ref _ref;
  Future<SignOutRequestResult>? _activeSignOut;

  Future<SignOutRequestResult> signOut() {
    final active = _activeSignOut;
    if (active != null) return active;
    late final Future<SignOutRequestResult> operation;
    operation = _signOut().then((_) => SignOutRequestResult.completed).whenComplete(
      () {
        if (identical(_activeSignOut, operation)) {
          _activeSignOut = null;
        }
      },
    );
    _activeSignOut = operation;
    return operation;
  }

  Future<void> _signOut() async {
    FullAppDataClearOutcome? outcome;

    void resumeGlobalAdmission() {
      PreferencesStore.resumeWritesAfterAppDataClear();
    }

    Future<void> prepareForClear() async {
      try {
        await PreferencesStore.blockWritesForAppDataClear();
      } catch (_) {
        resumeGlobalAdmission();
        rethrow;
      }
    }

    // Every saved account goes, not just the active one: end their sessions
    // on the server too, listed now while the registry still names them.
    final inactiveSessions = await _ref
        .read(authStateManagerProvider.notifier)
        .inactiveAccountSessions();

    try {
      outcome = await _ref
          .read(authStateManagerProvider.notifier)
          .logoutAndClearAppData(
            keepServerDetails: true,
            beforeClear: prepareForClear,
          );
      switch (outcome) {
        case FullAppDataClearOutcome.cleared ||
            FullAppDataClearOutcome.localDataClearedSessionCleanupIncomplete:
          await _purgeAccountDatabases();
          unawaited(
            _ref
                .read(authStateManagerProvider.notifier)
                .revokeSessions(inactiveSessions),
          );
          _resetProvidersAfterFullAppDataClear(_ref);
        case FullAppDataClearOutcome.incomplete:
          // The wipe committed as far as it could; what survived is the
          // server's own detail, which the next boot re-seeds anyway.
          break;
        case FullAppDataClearOutcome.ownershipYielded:
          resumeGlobalAdmission();
      }
    } finally {
      // The barrier only ever guarded preference writes; the account database
      // purge deletes files and needs no barrier held.
      resumeGlobalAdmission();
    }
  }

  /// Deletes every account's database. Ending a session no longer deletes
  /// one, so this is what removes them: all of them, whether or not the
  /// account registry can still name them. If that keeps failing, the next
  /// start finishes the job before any database opens.
  Future<void> _purgeAccountDatabases() async {
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _ref.read(openWebUiDatabaseSweepProvider)();
        return;
      } catch (error, stackTrace) {
        DebugLogger.error(
          'sign-out-account-database-purge-failed',
          scope: 'auth/sign-out',
          error: error,
          stackTrace: stackTrace,
          data: {'attempt': attempt},
        );
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
        }
      }
    }
    // Name the files left, so the next start deletes those and not an account
    // signed in to after this.
    Set<String>? leftover;
    try {
      leftover = await _ref.read(openWebUiDatabaseFilesProvider)();
    } catch (_) {}
    try {
      // Kept closed in this run too: an account signed in to again here has
      // the same file, and would lose what it wrote at the next start.
      await _ref.read(databaseManagerProvider).recordPendingWipe(leftover);
    } catch (error, stackTrace) {
      DebugLogger.error(
        'sign-out-pending-database-wipe-failed',
        scope: 'auth/sign-out',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// A single, value-deduplicated auth dependency for model resolution. Watching
/// the three public derivations independently can restart an async provider
/// several times while one AuthState transition is being published.
final _modelAuthReadinessProvider = Provider<_ModelAuthReadiness>((ref) {
  return (
    authenticated: ref.watch(isAuthenticatedProvider2),
    loading: ref.watch(isAuthLoadingProvider2),
    status: ref.watch(authStatusProvider),
  );
});

bool _modelAuthRetainsOpenWebUiSession(_ModelAuthReadiness auth) =>
    auth.authenticated;

bool _modelAuthIsPending(_ModelAuthReadiness auth) =>
    auth.loading ||
    auth.status == AuthStatus.initial ||
    auth.status == AuthStatus.loading;
