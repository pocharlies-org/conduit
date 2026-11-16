part of 'app_providers.dart';

// Provider to automatically load and set the default model from user settings or OpenWebUI
@Riverpod(keepAlive: true)
Future<Model?> defaultModel(Ref ref) async {
  Model? resolved;
  var ownerRetries = 0;
  while (true) {
    final reviewerAtStart = ref.read(reviewerModeProvider);
    final selectedAtStart = ref.read(selectedModelProvider);
    final manualAtStart = ref.read(isManualModelSelectionProvider);
    final apiAtStart = ref.read(apiServiceProvider);
    final ownerAtStart = apiAtStart == null
        ? null
        : captureOpenWebUiCacheOwnership(
            ref,
            api: apiAtStart,
            requireAuthenticated: false,
          );
    final candidate = await _resolveDefaultModel(ref);
    if (!ref.mounted) return null;

    // A session that settled while this ran -- the same account and token,
    // its database certified meanwhile -- makes the resolver drop its result
    // as another owner's, and nothing asks again. Resolve once more for it,
    // unless the selection moved meanwhile. A different session is left to
    // its own resolution.
    if (ownerAtStart != null &&
        ownerRetries < 2 &&
        !openWebUiCacheOwnershipIsCurrent(ref, ownerAtStart) &&
        ref.read(isAuthenticatedProvider2) &&
        ref.read(authTokenProvider3) == ownerAtStart.authToken &&
        ref.read(activeServerProvider).value?.id ==
            ownerAtStart.activeServerId &&
        identical(ref.read(selectedModelProvider), selectedAtStart) &&
        !ref.read(isManualModelSelectionProvider)) {
      ownerRetries++;
      continue;
    }

    if (ref.read(reviewerModeProvider) != reviewerAtStart) {
      final latestSelected = ref.read(selectedModelProvider);
      final latestManual = ref.read(isManualModelSelectionProvider);
      final hasNewManualSelection =
          latestSelected != null &&
          latestManual &&
          (!manualAtStart || !identical(latestSelected, selectedAtStart));
      if (hasNewManualSelection) {
        resolved = latestSelected;
        break;
      }
      // The mode may change after the resolver's final internal checkpoint but
      // before this provider resumes its await. Loop once more so the cached
      // value and dependency watches belong to the current reviewer universe.
      continue;
    }
    resolved = candidate;
    break;
  }

  // Register reactive dependencies only after async resolution settles. A
  // later input change invalidates the cached result, while a change during an
  // in-flight one-shot `.future` read cannot cancel and orphan that read.
  ref.watch(apiServiceProvider);
  ref.watch(_modelAuthReadinessProvider);
  ref.watch(reviewerModeProvider);
  ref.watch(modelsProvider);
  return resolved;
}

Future<Model?> _resolveDefaultModel(Ref ref) async {
  DebugLogger.log('provider-called', scope: 'models/default');

  final storage = ref.read(optimizedStorageServiceProvider);
  // This provider is commonly consumed through a one-shot `.future` read.
  // Snapshot mutable inputs instead of subscribing across awaits: invalidating
  // an in-flight build can otherwise orphan the caller's future. SelectedModel
  // owns reconciliation, and the post-await checks below reject stale
  // snapshots.
  final reviewerMode = ref.read(reviewerModeProvider);
  final selectedAtResolutionStart = ref.read(selectedModelProvider);
  final manualAtResolutionStart = ref.read(isManualModelSelectionProvider);
  final restoreOwnerIsCurrent = ref.read(defaultModelRestoreGuardProvider);

  bool isGenuinelyNewManualSelection(
    Model? latestSelected,
    bool latestManual,
  ) =>
      latestSelected != null &&
      latestManual &&
      (!manualAtResolutionStart ||
          !identical(latestSelected, selectedAtResolutionStart));

  Future<Model?>? reviewerRedirectAfterAwait() {
    if (ref.read(reviewerModeProvider) == reviewerMode) return null;
    final latestSelected = ref.read(selectedModelProvider);
    final latestManual = ref.read(isManualModelSelectionProvider);
    if (isGenuinelyNewManualSelection(latestSelected, latestManual)) {
      return Future<Model?>.value(latestSelected);
    }
    // Re-enter from the current reviewer state instead of caching an automatic
    // selection from the reviewer universe that owned the completed await.
    return _resolveDefaultModel(ref);
  }

  if (reviewerMode) {
    DebugLogger.log('reviewer-mode', scope: 'models/default');
    // Check if a model is manually selected
    final currentSelected = selectedAtResolutionStart;
    final isManualSelection = manualAtResolutionStart;

    if (currentSelected != null && isManualSelection) {
      DebugLogger.log(
        'manual',
        scope: 'models/default',
        data: {'source': 'user'},
      );
      return currentSelected;
    }

    // Get demo models and select the first one
    final models = await ref.read(modelsProvider.future);
    if (!ref.mounted) return null;
    final reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    final latestSelected = ref.read(selectedModelProvider);
    final latestManual = ref.read(isManualModelSelectionProvider);
    if (isGenuinelyNewManualSelection(latestSelected, latestManual)) {
      return latestSelected;
    }
    if (!identical(latestSelected, currentSelected) ||
        latestManual != isManualSelection) {
      return _resolveDefaultModel(ref);
    }
    if (models.isNotEmpty) {
      final defaultModel = models.first;
      if (!isManualSelection) {
        ref.read(selectedModelProvider.notifier).set(defaultModel);
        DebugLogger.log(
          'auto-select',
          scope: 'models/default',
          data: {'source': 'reviewer'},
        );
      }
      return defaultModel;
    }
    DebugLogger.warning('no-demo-models', scope: 'models/default');
    return null;
  }

  final api = ref.read(apiServiceProvider);
  var modelAuth = ref.read(_modelAuthReadinessProvider);
  final selectedBeforeAuthSettles = ref.read(selectedModelProvider);
  final authBuildFuture =
      !modelAuth.authenticated &&
          modelAuth.loading &&
          selectedBeforeAuthSettles == null
      ? ref.read(authStateManagerProvider.future)
      : null;
  if (authBuildFuture != null) {
    // A cold-start chat may ask for its default before the initial secure
    // storage read resolves. If this invocation completes with null, there may
    // be no remaining listener to retry when auth settles. Wait for that first
    // AuthStateManager build; inner token refreshes already have AsyncData and
    // return immediately.
    final settledAuth = await authBuildFuture;
    if (!ref.mounted) return null;
    final reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    modelAuth = (
      authenticated: settledAuth.isAuthenticated,
      loading:
          settledAuth.isLoading ||
          settledAuth.status == AuthStatus.initial ||
          settledAuth.status == AuthStatus.loading,
      status: settledAuth.status,
    );
  }
  if (!modelAuth.authenticated) {
    if (!_shouldUseAccountlessModelSelection(
      isAuthenticated: false,
      isAuthLoading: modelAuth.loading,
      authStatus: modelAuth.status,
      hasApiService: api != null,
    )) {
      // Authentication hydration/revalidation is not logout. Keep the current
      // model and avoid protected OpenWebUI calls until auth settles.
      return await Future<Model?>.value(ref.read(selectedModelProvider));
    }

    final currentSelected = ref.read(selectedModelProvider);
    final configuredDefaultId =
        currentSelected != null && ref.read(isManualModelSelectionProvider)
        ? null
        : ref.read(appSettingsProvider).defaultModel;
    final models = await ref.read(modelsProvider.future);
    if (!ref.mounted) return null;
    final reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    final standalone = _accountlessSelection(
      models: models,
      current: currentSelected,
      preferredModelId: configuredDefaultId,
    );
    // Provider initialization may not synchronously mutate another provider.
    await Future<void>.delayed(Duration.zero);
    if (!ref.mounted) return null;
    final reviewerRedirectAfterDelay = reviewerRedirectAfterAwait();
    if (reviewerRedirectAfterDelay != null) {
      return await reviewerRedirectAfterDelay;
    }
    final latestSelected = ref.read(selectedModelProvider);
    final authStillAllowsAccountless = _shouldUseAccountlessModelSelection(
      isAuthenticated: ref.read(_modelAuthReadinessProvider).authenticated,
      isAuthLoading: ref.read(_modelAuthReadinessProvider).loading,
      authStatus: ref.read(_modelAuthReadinessProvider).status,
      hasApiService: ref.read(apiServiceProvider) != null,
    );
    if (!authStillAllowsAccountless ||
        !identical(latestSelected, currentSelected)) {
      return latestSelected;
    }
    if (!identical(currentSelected, standalone)) {
      if (currentSelected?.id != standalone?.id) {
        ref.read(isManualModelSelectionProvider.notifier).set(false);
      }
      ref.read(selectedModelProvider.notifier).set(standalone);
    }
    if (standalone != null) return standalone;
    DebugLogger.warning('no-accountless-model', scope: 'models/default');
    return null;
  }

  // Accountless selection is independent from the optional OpenWebUI server.
  // Authenticated work captures a point-in-time ownership token below;
  // startup/account listeners invalidate this provider when a fresh
  // resolution is required, so no server dependency needs to be watched across
  // the authentication await above.
  final authenticatedTokenSnapshot = ref.read(authTokenProvider3);
  final apiSnapshot = api;
  final authenticatedOwnershipSnapshot = api == null
      ? null
      : captureOpenWebUiCacheOwnership(
          ref,
          api: api,
          requireAuthenticated: false,
        );

  bool authenticatedResolutionIsCurrent(Model? selectionSnapshot) {
    if (!ref.mounted) return false;
    final latestAuth = ref.read(_modelAuthReadinessProvider);
    final ownershipIsCurrent = apiSnapshot == null
        ? authenticatedOwnershipSnapshot == null
        : authenticatedOwnershipSnapshot != null &&
              openWebUiCacheOwnershipIsCurrent(
                ref,
                authenticatedOwnershipSnapshot,
              );
    return latestAuth.authenticated &&
        ownershipIsCurrent &&
        (restoreOwnerIsCurrent?.call() ?? true) &&
        ref.read(authTokenProvider3) == authenticatedTokenSnapshot &&
        identical(ref.read(apiServiceProvider), apiSnapshot) &&
        identical(ref.read(selectedModelProvider), selectionSnapshot);
  }

  if (api == null) {
    final manuallySelected = ref.read(selectedModelProvider);
    if (ref.read(isManualModelSelectionProvider) && manuallySelected != null) {
      return manuallySelected;
    }

    final selectionSnapshot = ref.read(selectedModelProvider);
    final models = await ref.read(modelsProvider.future);
    if (!ref.mounted) return null;
    final reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
      return await Future<Model?>.value(ref.read(selectedModelProvider));
    }
    final standalone = models.firstOrNull;
    if (standalone != null && !ref.read(isManualModelSelectionProvider)) {
      ref.read(selectedModelProvider.notifier).set(standalone);
      return standalone;
    }
    DebugLogger.warning('no-api', scope: 'models/default');
    return null;
  }

  DebugLogger.log('api-available', scope: 'models/default');

  try {
    // Respect manual selection if present
    if (ref.read(isManualModelSelectionProvider)) {
      final current = ref.read(selectedModelProvider);
      if (current != null && !current.isHidden) return current;
      ref.read(isManualModelSelectionProvider.notifier).set(false);
      ref.read(selectedModelProvider.notifier).clear();
    }
    final selectionSnapshot = ref.read(selectedModelProvider);

    // 1) Priority: app-local default model preference.
    final settingsDefaultId = ref.read(appSettingsProvider).defaultModel;
    final storedDefaultId =
        settingsDefaultId ??
        await SettingsService.getDefaultModel().catchError((_) => null);
    if (!ref.mounted) return null;
    var reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
      return await Future<Model?>.value(ref.read(selectedModelProvider));
    }

    if (storedDefaultId != null && storedDefaultId.isNotEmpty) {
      final availableModels = await ref.read(modelsProvider.future);
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
      if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
        return await Future<Model?>.value(ref.read(selectedModelProvider));
      }
      final availableMatch = availableModels
          .where((model) => model.id == storedDefaultId)
          .firstOrNull;
      if (availableMatch != null && !ref.read(isManualModelSelectionProvider)) {
        ref.read(selectedModelProvider.notifier).set(availableMatch);
        unawaited(
          storage.saveLocalDefaultModel(availableMatch).onError((
            error,
            stack,
          ) {
            DebugLogger.error(
              'Failed to save default model to cache',
              scope: 'models/default',
              error: error,
              stackTrace: stack,
            );
          }),
        );
        DebugLogger.log(
          'settings-default',
          scope: 'models/default',
          data: {'source': 'available'},
        );
        return availableMatch;
      }
      final cachedMatch = await selectCachedModel(storage, storedDefaultId);
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
      if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
        return await Future<Model?>.value(ref.read(selectedModelProvider));
      }
      if (cachedMatch != null && !ref.read(isManualModelSelectionProvider)) {
        ref.read(selectedModelProvider.notifier).set(cachedMatch);
        unawaited(
          storage.saveLocalDefaultModel(cachedMatch).catchError((_) {}),
        );
        DebugLogger.log(
          'settings-default',
          scope: 'models/default',
          data: {'source': 'settings'},
        );
        return cachedMatch;
      }
    }

    // 2) Fallback: cached resolved default model (offline/fast startup).
    try {
      final cached = await storage.getLocalDefaultModel();
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
      if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
        return await Future<Model?>.value(ref.read(selectedModelProvider));
      }
      if (cached != null && !ref.read(isManualModelSelectionProvider)) {
        final cachedMatch = await selectCachedModel(storage, cached.id);
        if (!ref.mounted) return null;
        reviewerRedirect = reviewerRedirectAfterAwait();
        if (reviewerRedirect != null) return await reviewerRedirect;
        if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
          return await Future<Model?>.value(ref.read(selectedModelProvider));
        }
        if (cachedMatch == null) {
          await storage.saveLocalDefaultModel(null);
          if (!ref.mounted) return null;
          reviewerRedirect = reviewerRedirectAfterAwait();
          if (reviewerRedirect != null) return await reviewerRedirect;
          if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
            return await Future<Model?>.value(ref.read(selectedModelProvider));
          }
        } else {
          ref.read(selectedModelProvider.notifier).set(cachedMatch);
          DebugLogger.log(
            'cached-default',
            scope: 'models/default',
            data: {'source': 'cache'},
          );
          return cachedMatch;
        }
      }
    } catch (_) {
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
      if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
        return await Future<Model?>.value(ref.read(selectedModelProvider));
      }
    }

    // 3) Fallback: server-provided automatic resolution when no app-local
    // preference exists.
    try {
      final serverDefault = await api.getDefaultModel();
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
      if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
        return await Future<Model?>.value(ref.read(selectedModelProvider));
      }
      if (serverDefault != null && serverDefault.isNotEmpty) {
        final availableModels = await ref.read(modelsProvider.future);
        if (!ref.mounted) return null;
        reviewerRedirect = reviewerRedirectAfterAwait();
        if (reviewerRedirect != null) return await reviewerRedirect;
        if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
          return await Future<Model?>.value(ref.read(selectedModelProvider));
        }
        Model? resolved = availableModels
            .where((model) => model.id == serverDefault)
            .firstOrNull;
        if (resolved == null) {
          final models = await api.getModels();
          if (!ref.mounted) return null;
          reviewerRedirect = reviewerRedirectAfterAwait();
          if (reviewerRedirect != null) return await reviewerRedirect;
          if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
            return await Future<Model?>.value(ref.read(selectedModelProvider));
          }
          resolved = resolveSafeRemoteDefaultModel(models, serverDefault);
        }

        if (resolved != null && !ref.read(isManualModelSelectionProvider)) {
          ref.read(selectedModelProvider.notifier).set(resolved);
          unawaited(
            storage.saveLocalDefaultModel(resolved).onError((error, stack) {
              DebugLogger.error(
                'Failed to save default model to cache',
                scope: 'models/default',
                error: error,
                stackTrace: stack,
              );
            }),
          );
          DebugLogger.log(
            'server-default',
            scope: 'models/default',
            data: {'source': 'server'},
          );
          return resolved;
        }
      }
    } catch (_) {
      if (!ref.mounted) return null;
      reviewerRedirect = reviewerRedirectAfterAwait();
      if (reviewerRedirect != null) return await reviewerRedirect;
    }

    // 4) Fallback: fetch models and pick first available
    DebugLogger.log('fallback-path', scope: 'models/default');
    final models = await ref.read(modelsProvider.future);
    if (!ref.mounted) return null;
    reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    if (!authenticatedResolutionIsCurrent(selectionSnapshot)) {
      return await Future<Model?>.value(ref.read(selectedModelProvider));
    }
    DebugLogger.log(
      'models-loaded',
      scope: 'models/default',
      data: {'count': models.length},
    );
    final selectedModel = models.firstOrNull;
    if (selectedModel == null) {
      DebugLogger.warning('no-models', scope: 'models/default');
      return null;
    }
    if (!ref.read(isManualModelSelectionProvider)) {
      ref.read(selectedModelProvider.notifier).set(selectedModel);
      unawaited(
        storage.saveLocalDefaultModel(selectedModel).onError((error, stack) {
          DebugLogger.error(
            'Failed to save default model to cache',
            scope: 'models/default',
            error: error,
            stackTrace: stack,
          );
        }),
      );
      DebugLogger.log(
        'fallback-selected',
        scope: 'models/default',
        data: {'source': 'fallback'},
      );
    } else {
      DebugLogger.log('skip-manual-override', scope: 'models/default');
    }
    return selectedModel;
  } catch (e) {
    if (!ref.mounted) return null;
    final reviewerRedirect = reviewerRedirectAfterAwait();
    if (reviewerRedirect != null) return await reviewerRedirect;
    DebugLogger.error('set-default-failed', scope: 'models/default', error: e);
    return null;
  }
}

Model? _accountlessSelection({
  required Iterable<Model> models,
  required Model? current,
  String? preferredModelId,
}) {
  final available = models.toList(growable: false);

  final preferredMatch = preferredModelId == null || preferredModelId.isEmpty
      ? null
      : available.where((model) => model.id == preferredModelId).firstOrNull;
  if (preferredMatch != null) return preferredMatch;

  final currentMatch = current == null
      ? null
      : available.where((model) => model.id == current.id).firstOrNull;
  if (currentMatch != null) return currentMatch;
  return available.firstOrNull;
}

bool _shouldUseAccountlessModelSelection({
  required bool isAuthenticated,
  required bool isAuthLoading,
  required AuthStatus authStatus,
  required bool hasApiService,
}) {
  if (isAuthenticated || isAuthLoading) return false;
  return switch (authStatus) {
    AuthStatus.unauthenticated ||
    AuthStatus.tokenExpired ||
    AuthStatus.credentialError => true,
    AuthStatus.error || AuthStatus.initial || AuthStatus.loading =>
      !hasApiService,
    AuthStatus.authenticated => false,
  };
}

/// Resolves a server-provided default from the models the server reported.
@visibleForTesting
Model? resolveSafeRemoteDefaultModel(
  List<Model> remoteModels,
  String? serverDefault,
) {
  final models = remoteModels;
  if (models.isEmpty) return null;

  if (serverDefault != null && serverDefault.isNotEmpty) {
    for (final model in models) {
      if (model.id == serverDefault) return model;
    }
    final byName = models.where((m) => m.name == serverDefault).toList();
    if (byName.length == 1) return byName.first;
  }
  return models.first;
}
