import 'dart:async';

import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/providers/app_providers.dart';

/// Whether chat can accept externally delivered work (shared content, home
/// widget and app shortcut actions, Siri/Shortcuts, Android assistant).
///
/// True with an authenticated Open WebUI session.
final chatEntryReadyProvider = Provider<bool>((ref) {
  return ref.watch(authNavigationStateProvider) ==
      AuthNavigationState.authenticated;
});

/// Waits up to [timeout] for [chatEntryReadyProvider] (and, with
/// [requireModel], a selected model) during a cold launch.
///
/// Native entry points can arrive while auth or model discovery are still
/// hydrating. Returns immediately when nothing is loading, so a signed-out
/// Open WebUI install is not delayed.
/// Model discovery can be slow on a cold start, so [requireModel] callers
/// get the same 30 s window as the home widget's cold-start wait.
Future<bool> waitForChatEntryReady(
  Ref ref, {
  bool requireModel = false,
  Duration? timeout,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(
    timeout ?? Duration(seconds: requireModel ? 30 : 5),
  );
  while (true) {
    if (!ref.mounted) return false;
    final ready = ref.read(chatEntryReadyProvider);
    final hasModel = !requireModel || ref.read(selectedModelProvider) != null;
    if (ready && hasModel) return true;
    if (!ready && !_chatEntryReadinessPending(ref)) return false;
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future<void>.delayed(pollInterval);
  }
}

bool _chatEntryReadinessPending(Ref ref) {
  if (ref.read(authNavigationStateProvider) == AuthNavigationState.loading) {
    return true;
  }
  return false;
}
