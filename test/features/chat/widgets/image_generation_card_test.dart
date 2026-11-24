/// Tests for the in-chat "create image" card: the provider picker comes from
/// the server, the prompt and size are editable before launching, and the
/// Upscale / Edit actions re-run through [ApiService.editImage]. The newest
/// result joins the composer tray as a remote attachment.
library;

import 'package:checks/checks.dart';
import 'package:conduit/features/chat/widgets/image_generation_card.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/auth/api_auth_interceptor.dart';
import 'package:conduit_core/features/chat/providers/attached_files_provider.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = ServerConfig(
  id: 'test',
  name: 'Test',
  url: 'http://localhost:0',
);

/// A decodable 1x1 PNG: [EnhancedImageAttachment] resolves a `data:`
/// attachment id locally, without the network.
const _pngDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeApi extends Fake implements ApiService {
  _FakeApi({this.failGenerate = false});

  final bool failGenerate;
  String? generatedPrompt;
  String? generatedModel;
  String? generatedSize;
  int editCalls = 0;
  String? lastEditPrompt;
  List<String>? lastEditImages;

  @override
  Future<List<Map<String, dynamic>>> generateImage({
    required String prompt,
    String? model,
    String? size,
    int? n,
    int? steps,
    String? negativePrompt,
  }) async {
    generatedPrompt = prompt;
    generatedModel = model;
    generatedSize = size;
    if (failGenerate) throw Exception('server said no');
    return [_file('img-1')];
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
    editCalls++;
    lastEditImages = images;
    lastEditPrompt = prompt;
    return [_file('img-2')];
  }

  @override
  Future<String> getFileContent(
    String fileId, {
    int? maxBytes,
    ApiAuthSnapshot? authSnapshot,
    CancelToken? cancelToken,
  }) async => _pngDataUrl;

  static Map<String, dynamic> _file(String id) => {
    'id': id,
    'url': _pngDataUrl,
    'content_type': 'image/png',
    'filename': '$id.png',
  };
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  List<Map<String, dynamic>> models = const [
    {'id': 'chatgpt-image-2', 'name': 'ChatGPT Images'},
    {'id': 'alibaba-z-image', 'name': 'Z-Image'},
  ],
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      apiServiceProvider.overrideWithValue(api),
      activeServerProvider.overrideWith((ref) => _server),
      openWebUiAuthSessionEpochProvider.overrideWith((ref) => Object()),
      imageModelsProvider.overrideWith((ref) async => models),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(TweakcnThemes.t3Chat),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: ImageGenerationCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container);
}

class _Harness {
  _Harness(this.container);
  final ProviderContainer container;

  List<String?> get trayFileIds => [
    for (final entry in container.read(attachedFilesProvider)) entry.fileId,
  ];
}

void main() {
  testWidgets('offers the server-provided image models before generating', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api);
    expect(find.byKey(const Key('image-card-provider-chatgpt-image-2')), findsOneWidget);
    expect(find.byKey(const Key('image-card-provider-alibaba-z-image')), findsOneWidget);
    expect(find.byKey(const Key('image-card-generate')), findsOneWidget);
  });

  testWidgets('generates with the picked provider, size and edited prompt', (
    tester,
  ) async {
    final api = _FakeApi();
    final harness = await _pump(tester, api: api);
    await tester.enterText(
      find.byKey(const Key('image-card-prompt')),
      'a red fox',
    );
    await tester.tap(find.byKey(const Key('image-card-provider-alibaba-z-image')));
    await tester.tap(find.byKey(const Key('image-card-size-1024x1536')));
    await tester.tap(find.byKey(const Key('image-card-generate')));
    await tester.pumpAndSettle();

    check(api.generatedPrompt).equals('a red fox');
    check(api.generatedModel).equals('alibaba-z-image');
    check(api.generatedSize).equals('1024x1536');
    check(harness.trayFileIds).contains('img-1');
    expect(find.byKey(const Key('image-card-result')), findsOneWidget);
  });

  testWidgets('upscale re-edits the result and swaps the tray attachment', (
    tester,
  ) async {
    final api = _FakeApi();
    final harness = await _pump(tester, api: api);
    await tester.enterText(find.byKey(const Key('image-card-prompt')), 'fox');
    await tester.tap(find.byKey(const Key('image-card-generate')));
    await tester.pumpAndSettle();

    final upscale = find.byKey(const Key('image-card-upscale'));
    await tester.ensureVisible(upscale);
    await tester.pumpAndSettle();
    await tester.tap(upscale);
    await tester.pumpAndSettle();

    check(api.editCalls).equals(1);
    check(api.lastEditPrompt).equals(imageCardUpscalePrompt);
    check(api.lastEditImages!).isNotEmpty();
    check(harness.trayFileIds)
      ..contains('img-2')
      ..not((it) => it.contains('img-1'));
  });

  testWidgets('edit asks for a prompt and applies it via editImage', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api);
    await tester.enterText(find.byKey(const Key('image-card-prompt')), 'fox');
    await tester.tap(find.byKey(const Key('image-card-generate')));
    await tester.pumpAndSettle();

    final edit = find.byKey(const Key('image-card-edit'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('image-card-edit-prompt')),
      'make it blue',
    );
    final apply = find.byKey(const Key('image-card-apply-edit'));
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();

    check(api.editCalls).equals(1);
    check(api.lastEditPrompt).equals('make it blue');
  });

  testWidgets('a failed generation shows the error state', (tester) async {
    final api = _FakeApi(failGenerate: true);
    await _pump(tester, api: api);
    await tester.enterText(find.byKey(const Key('image-card-prompt')), 'fox');
    await tester.tap(find.byKey(const Key('image-card-generate')));
    await tester.pumpAndSettle();

    final l10n = tester.element(find.byType(ImageGenerationCard));
    expect(
      find.text(AppLocalizations.of(l10n)!.imagesPlaygroundFailed),
      findsOneWidget,
    );
    expect(find.byKey(const Key('image-card-result')), findsNothing);
  });
}
