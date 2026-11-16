import 'dart:async';

import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/settings_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/chat/providers/chat_providers.dart';
import 'package:conduit/features/chat/widgets/modern_chat_input.dart';
import 'package:conduit_core/features/workspace/models/workspace_common.dart';
import 'package:conduit_core/features/workspace/models/workspace_resources.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('skill suggestions insert and send the OpenWebUI mention token', (
    tester,
  ) async {
    final api = _SkillApi((_) async => _skills(_codeReview));
    final sent = <String>[];
    await _pumpComposer(tester, api: api, onSend: sent.add);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(api.queries, ['code']);
    expect(find.text('Code Review'), findsOneWidget);
    expect(find.text('code-review'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('skill-suggestion-code-review')),
    );
    await tester.pump();
    expect(_composerText(tester), '\$Code Review ');

    await tester.enterText(find.byType(TextField), '\$Code Review check this');
    await tester.tap(find.byKey(const ValueKey('primary-btn-send')));
    await tester.pump();

    expect(sent, ['<\$code-review|Code Review> check this']);

    await tester.enterText(find.byType(TextField), '\$');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_composerText(tester), '\$Code Review ');
  });

  testWidgets('newer skill searches win when responses finish out of order', (
    tester,
  ) async {
    final first = Completer<WorkspacePagedResponse<WorkspaceSkillSummary>>();
    final second = Completer<WorkspacePagedResponse<WorkspaceSkillSummary>>();
    final api = _SkillApi(
      (query) => query == 'first' ? first.future : second.future,
    );
    await _pumpComposer(tester, api: api);

    await tester.enterText(find.byType(TextField), '\$first');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '\$second');
    await tester.pump(const Duration(milliseconds: 300));

    second.complete(
      _skills(
        const WorkspaceSkillSummary(
          id: 'second',
          name: 'Second Skill',
          userId: 'user',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Second Skill'), findsOneWidget);

    first.complete(
      _skills(
        const WorkspaceSkillSummary(
          id: 'first',
          name: 'First Skill',
          userId: 'user',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Second Skill'), findsOneWidget);
    expect(find.text('First Skill'), findsNothing);
  });

  testWidgets('inactive skills are not selectable', (tester) async {
    final api = _SkillApi(
      (_) async => const WorkspacePagedResponse(
        items: [
          _codeReview,
          WorkspaceSkillSummary(
            id: 'disabled',
            name: 'Disabled Skill',
            userId: 'user',
            isActive: false,
          ),
        ],
        total: 2,
      ),
    );
    await _pumpComposer(tester, api: api);

    await tester.enterText(find.byType(TextField), '\$');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Code Review'), findsOneWidget);
    expect(find.text('Disabled Skill'), findsNothing);
  });

  testWidgets('editing the end of a skill name removes its identity', (
    tester,
  ) async {
    final api = _SkillApi((_) async => _skills(_codeReview));
    final sent = <String>[];
    await _pumpComposer(tester, api: api, onSend: sent.add);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('skill-suggestion-code-review')),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '\$Code ReviewX ');
    await tester.tap(find.byKey(const ValueKey('primary-btn-send')));
    await tester.pump();

    expect(sent, ['\$Code ReviewX']);
  });

  testWidgets('deleting the skill delimiter preserves its identity', (
    tester,
  ) async {
    final api = _SkillApi((_) async => _skills(_codeReview));
    final sent = <String>[];
    await _pumpComposer(tester, api: api, onSend: sent.add);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('skill-suggestion-code-review')),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '\$Code Review');
    await tester.tap(find.byKey(const ValueKey('primary-btn-send')));
    await tester.pump();

    expect(sent, ['<\$code-review|Code Review>']);
  });

  testWidgets('retyping the skill delimiter preserves its identity', (
    tester,
  ) async {
    final api = _SkillApi((_) async => _skills(_codeReview));
    final sent = <String>[];
    await _pumpComposer(tester, api: api, onSend: sent.add);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('skill-suggestion-code-review')),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '\$Code Review');
    await tester.enterText(find.byType(TextField), '\$Code Review ');
    await tester.tap(find.byKey(const ValueKey('primary-btn-send')));
    await tester.pump();

    expect(sent, ['<\$code-review|Code Review>']);
  });

  testWidgets('Enter sends while skill suggestions are still loading', (
    tester,
  ) async {
    final pending = Completer<WorkspacePagedResponse<WorkspaceSkillSummary>>();
    final api = _SkillApi((_) => pending.future);
    final sent = <String>[];
    await _pumpComposer(tester, api: api, onSend: sent.add);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['\$code']);
    pending.complete(_skills(_codeReview));
    await tester.pump();
  });

  testWidgets('signed-out chats suppress OpenWebUI skill suggestions', (
    tester,
  ) async {
    final api = _SkillApi((_) async => _skills(_codeReview));
    await _pumpComposer(tester, api: api, authenticated: false);

    await tester.enterText(find.byType(TextField), '\$code');
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.queries, isEmpty);
    expect(find.byKey(const ValueKey('prompt-overlay')), findsNothing);
  });
}

const _codeReview = WorkspaceSkillSummary(
  id: 'code-review',
  name: 'Code Review',
  userId: 'user',
);

WorkspacePagedResponse<WorkspaceSkillSummary> _skills(
  WorkspaceSkillSummary skill,
) => WorkspacePagedResponse(items: [skill], total: 1);

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _pumpComposer(
  WidgetTester tester, {
  required _SkillApi api,
  Model model = const Model(id: 'server-model', name: 'Server Model'),
  ValueChanged<String>? onSend,
  bool authenticated = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedModelProvider.overrideWith(() => _SeededSelectedModel(model)),
        apiServiceProvider.overrideWithValue(api),
        authTokenProvider3.overrideWithValue('token'),
        isAuthenticatedProvider2.overrideWithValue(authenticated),
        appSettingsProvider.overrideWith(_SendOnEnterSettings.new),
        isChatStreamingProvider.overrideWithValue(false),
        webSearchAvailableProvider.overrideWithValue(false),
        imageGenerationAvailableProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ModernChatInput(onSendMessage: onSend ?? (_) {})),
      ),
    ),
  );
  await tester.pump();
}

final class _SendOnEnterSettings extends AppSettingsNotifier {
  @override
  AppSettings build() => const AppSettings(sendOnEnter: true);
}

final class _SeededSelectedModel extends SelectedModel {
  _SeededSelectedModel(this.model);

  final Model model;

  @override
  Model build() => model;
}

final class _SkillApi extends ApiService {
  _SkillApi(this.search)
    : super(
        serverConfig: const ServerConfig(
          id: 'server',
          name: 'Server',
          url: 'https://example.com',
        ),
        workerManager: WorkerManager(),
      );

  final Future<WorkspacePagedResponse<WorkspaceSkillSummary>> Function(
    String? query,
  )
  search;
  final queries = <String?>[];

  @override
  Future<Map<String, dynamic>> getUserSettings({Object? authSnapshot}) async =>
      const <String, dynamic>{};

  @override
  Future<WorkspacePagedResponse<WorkspaceSkillSummary>> getWorkspaceSkills({
    String? query,
    String? viewOption,
    int page = 1,
  }) {
    queries.add(query);
    return search(query);
  }
}
