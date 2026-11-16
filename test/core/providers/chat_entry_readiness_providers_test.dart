import 'package:checks/checks.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/providers/chat_entry_readiness_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container({required AuthNavigationState auth}) {
  final container = ProviderContainer(
    overrides: [authNavigationStateProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a signed-out Open WebUI install is not chat-ready', () {
    final container = _container(auth: AuthNavigationState.needsLogin);

    check(container.read(chatEntryReadyProvider)).isFalse();
  });

  test('an authenticated Open WebUI session is chat-ready', () {
    final container = _container(auth: AuthNavigationState.authenticated);

    check(container.read(chatEntryReadyProvider)).isTrue();
  });

  test('a signed-out Open WebUI install does not wait', () async {
    final container = _container(auth: AuthNavigationState.needsLogin);

    final started = DateTime.now();
    final ready = await waitForChatEntryReady(container.read(_refProvider));

    check(ready).isFalse();
    check(DateTime.now().difference(started))
        .isLessThan(const Duration(seconds: 1));
  });
}
