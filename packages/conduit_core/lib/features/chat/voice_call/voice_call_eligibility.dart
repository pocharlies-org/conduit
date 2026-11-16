import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:meta/meta.dart';

import 'package:conduit_core/models/model.dart';

import 'package:conduit_core/providers/app_providers.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';

enum VoiceCallEligibilityReason {
  eligible,
  modelRequired,
  authenticationRequired,
}

@immutable
class VoiceCallEligibility {
  const VoiceCallEligibility._({
    required this.reason,
    required this.model,
    this.errorMessage,
  });

  const VoiceCallEligibility.eligible(Model model)
    : this._(reason: VoiceCallEligibilityReason.eligible, model: model);

  const VoiceCallEligibility.blocked({
    required VoiceCallEligibilityReason reason,
    required String errorMessage,
    Model? model,
  }) : this._(reason: reason, model: model, errorMessage: errorMessage);

  final VoiceCallEligibilityReason reason;
  final Model? model;
  final String? errorMessage;

  bool get canStart => reason == VoiceCallEligibilityReason.eligible;
}

final class VoiceCallEligibilityResolutionCancelled implements Exception {
  const VoiceCallEligibilityResolutionCancelled();
}

/// Resolves voice eligibility for the selected Open WebUI model, which needs
/// an authenticated session on its server.
final voiceCallEligibilityProvider = Provider<VoiceCallEligibility>((ref) {
  final model = ref.watch(selectedModelProvider);
  if (model == null) {
    return const VoiceCallEligibility.blocked(
      reason: VoiceCallEligibilityReason.modelRequired,
      errorMessage: 'Choose a model before starting a voice call.',
    );
  }

  if (ref.watch(reviewerModeProvider)) {
    return VoiceCallEligibility.eligible(model);
  }

  if (ref.watch(authNavigationStateProvider) ==
      AuthNavigationState.authenticated) {
    return VoiceCallEligibility.eligible(model);
  }

  return VoiceCallEligibility.blocked(
    reason: VoiceCallEligibilityReason.authenticationRequired,
    model: model,
    errorMessage: 'Sign in to start a voice call.',
  );
});

/// Resolves transient startup state before returning the current admission
/// decision. Native entry points can arrive before secure storage, auth, or
/// default-model selection has finished hydrating.
Future<VoiceCallEligibility> resolveVoiceCallEligibility(
  Ref ref, {
  Duration readinessTimeout = const Duration(seconds: 3),
  Future<void>? cancellationSignal,
  bool Function()? cancellationRequested,
}) async {
  final deadline = DateTime.now().add(readinessTimeout);
  final cancellation = _VoiceCallEligibilityCancellation(
    signal: cancellationSignal,
    requested: cancellationRequested,
  );

  while (true) {
    cancellation.throwIfRequested();
    if (ref.read(authNavigationStateProvider) == AuthNavigationState.loading &&
        !voiceCallCanResolveWithoutOpenWebUiAuth(ref)) {
      final changed = await _waitForOpenWebUiStateChange(
        ref,
        deadline,
        cancellation,
      );
      cancellation.throwIfRequested();
      if (changed) continue;
      return ref.read(voiceCallEligibilityProvider);
    }

    await _resolveDefaultModelIfNeeded(ref, deadline, cancellation);
    cancellation.throwIfRequested();
    final eligibility = ref.read(voiceCallEligibilityProvider);
    if (eligibility.canStart ||
        ref.read(authNavigationStateProvider) != AuthNavigationState.loading ||
        voiceCallCanResolveWithoutOpenWebUiAuth(ref)) {
      return eligibility;
    }

    final changed = await _waitForOpenWebUiStateChange(
      ref,
      deadline,
      cancellation,
    );
    cancellation.throwIfRequested();
    if (!changed) return ref.read(voiceCallEligibilityProvider);
  }
}

/// Whether the current voice launch can become ready without OpenWebUI auth.
///
/// Every voice transport runs against the Open WebUI server, so only reviewer
/// mode proceeds while an OpenWebUI session is still hydrating.
bool voiceCallCanResolveWithoutOpenWebUiAuth(Ref ref) {
  return ref.read(reviewerModeProvider);
}

Duration _remainingReadinessTime(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  return remaining.isNegative ? Duration.zero : remaining;
}

Future<void> _resolveDefaultModelIfNeeded(
  Ref ref,
  DateTime deadline,
  _VoiceCallEligibilityCancellation cancellation,
) async {
  cancellation.throwIfRequested();
  if (ref.read(selectedModelProvider) != null) return;
  final remaining = _remainingReadinessTime(deadline);
  if (remaining == Duration.zero) return;
  try {
    await cancellation.wait(
      ref
          .read(defaultModelProvider.future)
          .timeout(remaining, onTimeout: () => null),
    );
  } on VoiceCallEligibilityResolutionCancelled {
    rethrow;
  } catch (_) {
    // The eligibility result below provides the user-facing failure.
  }
}

Future<bool> _waitForOpenWebUiStateChange(
  Ref ref,
  DateTime deadline,
  _VoiceCallEligibilityCancellation cancellation,
) async {
  cancellation.throwIfRequested();
  if (ref.read(authNavigationStateProvider) != AuthNavigationState.loading ||
      voiceCallCanResolveWithoutOpenWebUiAuth(ref)) {
    return true;
  }

  final completer = Completer<bool>();
  void completeOnChange(Object? previous, Object? next) {
    if (!completer.isCompleted) completer.complete(true);
  }

  final subscriptions = <ProviderSubscription<Object?>>[
    ref.listen<AuthNavigationState>(
      authNavigationStateProvider,
      completeOnChange,
    ),
    ref.listen<Model?>(selectedModelProvider, completeOnChange),
  ];
  final timer = Timer(_remainingReadinessTime(deadline), () {
    if (!completer.isCompleted) completer.complete(false);
  });
  if ((ref.read(authNavigationStateProvider) != AuthNavigationState.loading ||
          voiceCallCanResolveWithoutOpenWebUiAuth(ref)) &&
      !completer.isCompleted) {
    completer.complete(true);
  }

  try {
    return await cancellation.wait(completer.future);
  } finally {
    timer.cancel();
    for (final subscription in subscriptions) {
      subscription.close();
    }
  }
}

final class _VoiceCallEligibilityCancellation {
  const _VoiceCallEligibilityCancellation({this.signal, this.requested});

  final Future<void>? signal;
  final bool Function()? requested;

  void throwIfRequested() {
    if (requested?.call() ?? false) {
      throw const VoiceCallEligibilityResolutionCancelled();
    }
  }

  Future<T> wait<T>(Future<T> operation) async {
    throwIfRequested();
    final cancellationSignal = signal;
    if (cancellationSignal == null) return operation;
    return Future.any<T>([
      operation,
      cancellationSignal.then<T>(
        (_) => throw const VoiceCallEligibilityResolutionCancelled(),
      ),
    ]);
  }
}
