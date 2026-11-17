import 'dart:convert';

import 'package:conduit/features/images/views/image_playground_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/auth/api_auth_interceptor.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_fonts.dart';

/// A 1×1 transparent PNG, the smallest image the server could hand back.
final _pixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _PlaygroundApi extends ApiService {
  _PlaygroundApi()
    : super(
        serverConfig: const ServerConfig(
          id: 'test',
          name: 'Test',
          url: 'https://example.com',
        ),
        workerManager: WorkerManager(),
      );

  final List<String> generated = [];
  final List<List<String>> edited = [];

  @override
  Future<List<Map<String, dynamic>>> generateImage({
    required String prompt,
    String? model,
    String? size,
    int? n,
    int? steps,
    String? negativePrompt,
  }) async {
    generated.add(prompt);
    return [
      {'id': 'file-1', 'url': '/api/v1/files/file-1/content'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> editImage({
    required List<String> images,
    required String prompt,
    String? model,
    String? size,
    int? n,
    String? negativePrompt,
  }) async {
    edited.add(images);
    return [
      {'id': 'file-2', 'url': '/api/v1/files/file-2/content'},
    ];
  }

  @override
  Future<String> getFileContent(
    String fileId, {
    int? maxBytes,
    ApiAuthSnapshot? authSnapshot,
    CancelToken? cancelToken,
  }) async => 'data:image/png;base64,${base64Encode(_pixelPng)}';
}

Future<void> _pump(
  WidgetTester tester, {
  required _PlaygroundApi api,
  bool available = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      apiServiceProvider.overrideWithValue(api),
      imagesPlaygroundAvailableProvider.overrideWithValue(available),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ImagePlaygroundPage(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('says so when the server has no image generation', (
    tester,
  ) async {
    await _pump(tester, api: _PlaygroundApi(), available: false);

    expect(find.byKey(const Key('image-playground-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('image-playground-prompt')), findsNothing);
  });

  testWidgets('generates from the prompt and shows the result', (tester) async {
    final api = _PlaygroundApi();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const Key('image-playground-prompt')),
      'a cat on a roof',
    );
    await tester.tap(find.byKey(const Key('image-playground-run')));
    await tester.pump();
    await tester.pump();

    expect(api.generated, ['a cat on a roof']);
    expect(find.byKey(const Key('image-playground-result-0')), findsOneWidget);
  });

  testWidgets('asks for a prompt before calling the server', (tester) async {
    final api = _PlaygroundApi();
    await _pump(tester, api: api);

    await tester.tap(find.byKey(const Key('image-playground-run')));
    await tester.pump();

    expect(api.generated, isEmpty);
    expect(find.text('Enter a prompt.'), findsOneWidget);
  });
}