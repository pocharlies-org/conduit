part of 'app_providers.dart';

// Model providers

bool _sameModelCacheOwnership(
  OpenWebUiCacheOwnershipSnapshot? previous,
  OpenWebUiCacheOwnershipSnapshot next,
) =>
    previous != null &&
    identical(previous.api, next.api) &&
    previous.serverId == next.serverId &&
    previous.activeServerId == next.activeServerId &&
    identical(previous.authSessionEpoch, next.authSessionEpoch) &&
    previous.authToken == next.authToken &&
    previous.authenticated == next.authenticated &&
    previous.databaseAccessPhase == next.databaseAccessPhase &&
    previous.certifiedDatabaseServerId == next.certifiedDatabaseServerId &&
    previous.rawActiveServerId == next.rawActiveServerId;

@Riverpod(keepAlive: true)
class Models extends _$Models {
  Future<void>? _refreshInFlight;
  OpenWebUiCacheOwnershipSnapshot? _warmRefreshOwnership;

  @override
  Future<List<Model>> build() async {
    // Reviewer mode returns mock models
    if (ref.watch(reviewerModeProvider)) {
      return _demoModels();
    }

    final modelAuth = ref.watch(_modelAuthReadinessProvider);
    // `isAuthenticated` is false during a token-preserving refresh too. Watch
    // the richer auth signals so loading -> terminal sign-out triggers a
    // second reconciliation without clobbering a live selection in the
    // transient loading state.
    if (!modelAuth.authenticated && _modelAuthIsPending(modelAuth)) {
      // Pending credentials are not authority for cache/API work. Preserve an
      // already-rendered in-memory list until auth reaches a terminal state.
      final previous = state.value;
      if (previous != null) return previous;
      return _returnWithSelectionReconciliation(const <Model>[]);
    }
    if (!_modelAuthRetainsOpenWebUiSession(modelAuth)) {
      DebugLogger.log('skip-unauthed', scope: 'models');
      _persistModelsAsync(const <Model>[]);
      return _returnWithSelectionReconciliation(const <Model>[]);
    }

    // These ownership dependencies fence OpenWebUI cache/API work.
    ref.watch(openWebUiAuthSessionEpochProvider);
    ref.watch(openWebUiDatabaseAccessProvider);
    ref.watch(openWebUiCertifiedDatabaseServerProvider);
    ref.watch(activeServerProvider.select((value) => value.value?.id));

    final api = ref.watch(apiServiceProvider);
    final cacheOwnership = api == null
        ? null
        : captureOpenWebUiCacheOwnership(
            ref,
            api: api,
            requireAuthenticated: false,
          );
    if (api != null && cacheOwnership == null) {
      return _returnWithSelectionReconciliation(const <Model>[]);
    }
    final storage = ref.watch(optimizedStorageServiceProvider);
    try {
      final cached = await storage.getLocalModels();
      if (cacheOwnership != null &&
          !openWebUiCacheOwnershipIsCurrent(ref, cacheOwnership)) {
        return _returnWithSelectionReconciliation(const <Model>[]);
      }
      if (cached.isNotEmpty) {
        final visibleCached = _visibleModels(cached);
        DebugLogger.log(
          'cache-restored',
          scope: 'models/cache',
          data: {
            'count': visibleCached.length,
            'hidden': cached.length - visibleCached.length,
          },
        );
        if (visibleCached.length != cached.length && cacheOwnership != null) {
          _persistModelsAsync(visibleCached, ownership: cacheOwnership);
        }
        if (cacheOwnership != null &&
            !_sameModelCacheOwnership(_warmRefreshOwnership, cacheOwnership)) {
          _warmRefreshOwnership = cacheOwnership;
          Future.microtask(() async {
            if (!ref.mounted) return;
            try {
              await refresh();
            } catch (error, stackTrace) {
              DebugLogger.error(
                'warm-refresh-failed',
                scope: 'models/cache',
                error: error,
                stackTrace: stackTrace,
              );
            }
          });
        }
        return _returnWithSelectionReconciliation(visibleCached);
      }
    } catch (error, stackTrace) {
      DebugLogger.error(
        'cache-load-failed',
        scope: 'models/cache',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (api == null) {
      DebugLogger.warning('api-missing', scope: 'models');
      _persistModelsAsync(const <Model>[]);
      return _returnWithSelectionReconciliation(const <Model>[]);
    }

    try {
      final loaded = await _load(api);
      if (loaded == null ||
          !openWebUiCacheOwnershipIsCurrent(ref, loaded.ownership)) {
        return _returnWithSelectionReconciliation(const <Model>[]);
      }
      return _returnWithSelectionReconciliation(loaded.models);
    } catch (_) {
      _returnWithSelectionReconciliation(const <Model>[]);
      rethrow;
    }
  }

  List<Model> _returnWithSelectionReconciliation(List<Model> models) {
    unawaited(
      Future<void>(() {
        if (ref.mounted) {
          _reconcileLocalSelection(models);
        }
      }),
    );
    return models;
  }

  /// Keeps the selection bound to a model the current list can actually
  /// serve: an accountless list may only carry its own first model, and a
  /// missing Open WebUI model is replaced by another Open WebUI one.
  List<Model> _reconcileLocalSelection(List<Model> models) {
    final currentSelected = ref.read(selectedModelProvider);
    final modelAuth = ref.read(_modelAuthReadinessProvider);
    if (!modelAuth.authenticated) {
      final shouldReconcile = _shouldUseAccountlessModelSelection(
        isAuthenticated: false,
        isAuthLoading: modelAuth.loading,
        authStatus: modelAuth.status,
        hasApiService: ref.read(apiServiceProvider) != null,
      );
      if (!shouldReconcile) return models;

      final replacement = _accountlessSelection(
        models: models,
        current: currentSelected,
        preferredModelId:
            currentSelected != null && ref.read(isManualModelSelectionProvider)
            ? null
            : ref.read(appSettingsProvider).defaultModel,
      );
      if (identical(currentSelected, replacement)) return models;

      if (currentSelected?.id != replacement?.id) {
        ref.read(isManualModelSelectionProvider.notifier).set(false);
      }
      ref.read(selectedModelProvider.notifier).set(replacement);
      DebugLogger.warning(
        'accountless-selection-reconciled',
        scope: 'models',
        data: {'source': 'reconciliation'},
      );
      return models;
    }
    return models;
  }

  Future<void> refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    late final Future<void> operation;
    operation = _refresh().whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = operation;
    return operation;
  }

  Future<void> _refresh() async {
    if (ref.read(reviewerModeProvider)) {
      state = AsyncData<List<Model>>(_demoModels());
      return;
    }
    final modelAuth = ref.read(_modelAuthReadinessProvider);
    if (!modelAuth.authenticated && _modelAuthIsPending(modelAuth)) {
      // An explicit refresh during login/revalidation is deferred. This keeps
      // the current in-memory list intact without treating retained or
      // candidate credentials as permission to touch OpenWebUI cache/API data.
      return;
    }
    if (!_modelAuthRetainsOpenWebUiSession(modelAuth)) {
      state = const AsyncData<List<Model>>([]);
      _persistModelsAsync(const <Model>[]);
      return;
    }
    final api = ref.read(apiServiceProvider);
    if (api == null) {
      state = const AsyncData<List<Model>>([]);
      _persistModelsAsync(const <Model>[]);
      return;
    }
    final result = await AsyncValue.guard(() => _load(api));
    if (!ref.mounted) return;
    final loaded = result.value;
    if (result.hasValue &&
        (loaded == null ||
            !openWebUiCacheOwnershipIsCurrent(ref, loaded.ownership))) {
      return;
    }
    state = result.whenData((owned) => owned!.models);

    // Update selected model with fresh data (e.g., filters) if it exists
    // in the new models list
    final currentState = state;
    if (currentState.hasValue) {
      final freshModels = currentState.value!;
      final currentSelected = ref.read(selectedModelProvider);
      if (currentSelected != null) {
        if (currentSelected.isHidden) {
          return;
        }
        try {
          final freshModel = freshModels.firstWhere(
            (m) => m.id == currentSelected.id,
          );
          // Update selected model with fresh data (filters, etc.)
          if (freshModel != currentSelected) {
            ref.read(selectedModelProvider.notifier).set(freshModel);
            DebugLogger.log(
              'selected-model-refreshed',
              scope: 'models',
              data: {
                'filters': freshModel.filters?.length ?? 0,
                'source': 'refresh',
              },
            );
          }
        } catch (_) {
          final replacement = freshModels.firstOrNull;
          ref.read(isManualModelSelectionProvider.notifier).set(false);
          ref.read(selectedModelProvider.notifier).set(replacement);
          DebugLogger.warning(
            'selected-model-unavailable',
            scope: 'models',
            data: {'source': 'refresh'},
          );
        }
      }
    }
  }

  Future<_OwnedModels?> _load(ApiService api) async {
    final ownership = captureOpenWebUiCacheOwnership(
      ref,
      api: api,
      requireAuthenticated: false,
    );
    if (ownership == null) return null;
    try {
      DebugLogger.log('fetch-start', scope: 'models');
      final models = await api.getModels();
      if (!openWebUiCacheOwnershipIsCurrent(ref, ownership)) return null;
      final visibleModels = _visibleModels(models);
      DebugLogger.log(
        'fetch-ok',
        scope: 'models',
        data: {
          'count': visibleModels.length,
          'hidden': models.length - visibleModels.length,
        },
      );
      _warmRefreshOwnership = ownership;
      _persistModelsAsync(visibleModels, ownership: ownership);
      return (models: visibleModels, ownership: ownership);
    } catch (e, stackTrace) {
      DebugLogger.error(
        'fetch-failed',
        scope: 'models',
        error: e,
        stackTrace: stackTrace,
      );

      // If models endpoint returns 403, this should now clear auth token
      // and redirect user to login since it's marked as a core endpoint
      if (e.toString().contains('403')) {
        DebugLogger.warning('endpoint-403', scope: 'models');
      }
      // Preserve an existing selection on transient refresh failures: an
      // empty successful result here could silently switch an OpenWebUI
      // conversation to another model.
      rethrow;
    }
  }

  List<Model> _visibleModels(List<Model> models) {
    if (models.isEmpty) return const <Model>[];
    return models.where((model) => !model.isHidden).toList();
  }

  void _persistModelsAsync(
    List<Model> models, {
    OpenWebUiCacheOwnershipSnapshot? ownership,
  }) {
    if (ownership != null &&
        !openWebUiCacheOwnershipIsCurrent(ref, ownership)) {
      return;
    }
    final storage = ref.read(optimizedStorageServiceProvider);
    unawaited(
      storage.saveLocalModels(models).onError((error, stack) {
        DebugLogger.error(
          'Failed to persist models to cache',
          scope: 'models/cache',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  List<Model> _demoModels() => const [
    Model(
      id: 'demo/gemma-2-mini',
      name: 'Gemma 2 Mini (Demo)',
      description: 'Demo model for reviewer mode',
      isMultimodal: true,
      supportsStreaming: true,
      supportedParameters: ['max_tokens', 'stream'],
    ),
    Model(
      id: 'demo/llama-3-8b',
      name: 'Llama 3 8B (Demo)',
      description: 'Fast text model for demo',
      isMultimodal: false,
      supportsStreaming: true,
      supportedParameters: ['max_tokens', 'stream'],
    ),
  ];
}

typedef _OwnedModels = ({
  List<Model> models,
  OpenWebUiCacheOwnershipSnapshot ownership,
});

@Riverpod(keepAlive: true)
class SelectedModel extends _$SelectedModel {
  bool _authenticatedDefaultRestoreScheduled = false;

  @override
  Model? build() {
    // This provider is consumed before auth and secure secrets finish
    // hydrating on a cold start. Reconcile again when either one settles;
    // callers such as the chat page only await defaultModelProvider once.
    ref.listen<_ModelAuthReadiness>(_modelAuthReadinessProvider, (
      previous,
      next,
    ) {
      if (next.authenticated) {
        _scheduleAuthenticatedDefaultRestore();
      }
    });
    ref.listen<ApiService?>(apiServiceProvider, (previous, next) {
      if (next != null) _scheduleAuthenticatedDefaultRestore();
    });
    ref.listen<String?>(authTokenProvider3, (previous, next) {
      if (previous != next &&
          ref.read(_modelAuthReadinessProvider).authenticated) {
        _scheduleAuthenticatedDefaultRestore();
      }
    });
    return null;
  }

  void _scheduleAuthenticatedDefaultRestore() {
    if (_authenticatedDefaultRestoreScheduled) return;
    _authenticatedDefaultRestoreScheduled = true;
    unawaited(
      Future<void>.microtask(() {
        _authenticatedDefaultRestoreScheduled = false;
        if (!ref.mounted) return;
        if (state != null) return;
        final auth = ref.read(_modelAuthReadinessProvider);
        if (!auth.authenticated || ref.read(apiServiceProvider) == null) return;

        // A background saved-credential login can finish after an earlier
        // one-shot read cached null. Force a fresh authenticated resolution.
        // Dispatch instead of awaiting so a later token/session transition can
        // invalidate this attempt and immediately start the authoritative one.
        ref.invalidate(defaultModelProvider);
        final restore = ref.read(defaultModelProvider.future);
        unawaited(
          restore.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              if (!ref.mounted) return;
              DebugLogger.error(
                'authenticated-default-restore-failed',
                scope: 'models/default',
                error: error,
                stackTrace: stackTrace,
              );
            },
          ),
        );
      }),
    );
  }

  void set(Model? model, {bool allowHidden = false}) {
    if (model?.isHidden == true && !allowHidden) {
      state = null;
      return;
    }
    state = model;
  }

  void clear() => state = null;
}
