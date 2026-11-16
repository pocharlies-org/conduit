import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/providers/chat_providers.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for a non-null [ApiService] (we only care about non-null identity).
class _FakeApiService extends Fake implements ApiService {}

const _owuiModel = Model(id: 'gpt-4', name: 'GPT-4');

/// Unit tests for the extracted send/regenerate guard.
void main() {
  group('isSendBlocked', () {
    test('blocks when no model is selected', () {
      check(isSendBlocked(reviewerMode: false, api: null, selectedModel: null))
          .isTrue();
      // ...even with an api present.
      check(
        isSendBlocked(
          reviewerMode: false,
          api: _FakeApiService(),
          selectedModel: null,
        ),
      ).isTrue();
    });

    test('blocks an OWUI model when the api is null and not reviewer', () {
      check(
        isSendBlocked(
          reviewerMode: false,
          api: null,
          selectedModel: _owuiModel,
        ),
      ).isTrue();
    });

    test('allows an OWUI model when the api is present', () {
      check(
        isSendBlocked(
          reviewerMode: false,
          api: _FakeApiService(),
          selectedModel: _owuiModel,
        ),
      ).isFalse();
    });

    test('allows any model in reviewer mode even with a null api', () {
      check(
        isSendBlocked(reviewerMode: true, api: null, selectedModel: _owuiModel),
      ).isFalse();
    });

    test('allows a server model resembling the direct namespace', () {
      const serverModel = Model(
        id: 'direct:profile-one:bG9jYWwtbW9kZWw',
        name: 'Server-owned direct-like model',
        metadata: {
          'backend': 'direct',
          'direct': true,
          'directProvider': 'server-owned',
        },
      );

      check(
        isSendBlocked(
          reviewerMode: false,
          api: _FakeApiService(),
          selectedModel: serverModel,
        ),
      ).isFalse();
    });
  });
}
