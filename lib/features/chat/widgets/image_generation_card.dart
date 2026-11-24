import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit/features/chat/widgets/enhanced_image_attachment.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/action_card.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit_core/features/chat/providers/attached_files_provider.dart';
import 'package:conduit_core/models/file_info.dart';
import 'package:conduit_core/providers/app_providers.dart';

/// The size choices offered on the card, as OpenAI `size` values; the Studio
/// facade maps them to its aspect ratios.
const imageCardSizes = <String, String>{
  '1024x1024': '1:1',
  '1024x1536': '2:3',
  '1536x1024': '3:2',
};

/// The instruction the upscale action sends: the facade has no dedicated
/// upscale route, so the engine re-renders the same image with more detail.
const imageCardUpscalePrompt =
    'Upscale this image: keep the exact composition, subjects and colors, '
    'and render with higher resolution and sharper detail.';

/// Chat card for "create an image": asks which image provider the server
/// offers (and lets the prompt and size be edited) before generating, then
/// shows the result with working Upscale and Edit actions. The latest result
/// joins the conversation through the composer's attachment tray.
class ImageGenerationCard extends ConsumerStatefulWidget {
  const ImageGenerationCard({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  ConsumerState<ImageGenerationCard> createState() =>
      ImageGenerationCardState();
}

@visibleForTesting
class ImageGenerationCardState extends ConsumerState<ImageGenerationCard> {
  String? _model;
  String _size = '1024x1024';
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _editPrompt = TextEditingController();
  bool _busy = false;
  bool _editing = false;
  String? _error;
  Map<String, dynamic>? _result;
  String? _attachedFileId;

  @override
  void dispose() {
    _prompt.dispose();
    _editPrompt.dispose();
    super.dispose();
  }

  Future<String> _resultDataUrl() async {
    final api = ref.read(apiServiceProvider);
    final id = _result?['id'];
    if (api == null || id is! String || id.isEmpty) {
      throw const FormatException('No generated image to work on');
    }
    return api.getFileContent(id);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(() async {
    final api = ref.read(apiServiceProvider);
    final prompt = _prompt.text.trim();
    if (api == null || prompt.isEmpty) return;
    final files = await api.generateImage(
      prompt: prompt,
      model: _model,
      size: _size,
    );
    if (!mounted) return;
    _adopt(files);
  });

  Future<void> _upscale() => _run(() async {
    final api = ref.read(apiServiceProvider);
    if (api == null) return;
    final dataUrl = await _resultDataUrl();
    final files = await api.editImage(
      images: [dataUrl],
      prompt: imageCardUpscalePrompt,
      model: _model,
      size: _size,
    );
    if (!mounted) return;
    _adopt(files);
  });

  Future<void> _applyEdit() => _run(() async {
    final api = ref.read(apiServiceProvider);
    final prompt = _editPrompt.text.trim();
    if (api == null || prompt.isEmpty) return;
    final dataUrl = await _resultDataUrl();
    final files = await api.editImage(
      images: [dataUrl],
      prompt: prompt,
      model: _model,
      size: _size,
    );
    if (!mounted) return;
    _adopt(files);
    _editPrompt.clear();
  });

  /// Shows the newest file and keeps the tray holding exactly the card's
  /// latest result: the previous one is removed as a remote attachment.
  void _adopt(List<Map<String, dynamic>> files) {
    if (files.isEmpty) return;
    final file = files.first;
    setState(() {
      _result = file;
      _editing = false;
    });
    final id = file['id'];
    if (id is! String || id.isEmpty) return;
    final notifier = ref.read(attachedFilesProvider.notifier);
    final previous = _attachedFileId;
    if (previous != null && previous != id) {
      notifier.removeFile('remote://$previous');
    }
    notifier.addRemoteFile(_fileInfo(file));
    _attachedFileId = id;
  }

  static FileInfo _fileInfo(Map<String, dynamic> file) {
    final id = (file['id'] as String?) ?? '';
    final mime = (file['content_type'] as String?) ?? 'image/png';
    final rawName = (file['filename'] as String?)?.trim();
    final filename = (rawName == null || rawName.isEmpty)
        ? '$id.${mime.split('/').last}'
        : rawName;
    final now = DateTime.now();
    return FileInfo(
      id: id,
      filename: filename,
      originalFilename: filename,
      size: (file['size'] as num?)?.toInt() ?? 0,
      mimeType: mime,
      createdAt: now,
      updatedAt: now,
    );
  }

  String _describe(Object error, AppLocalizations? l10n) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    }
    return l10n?.imagesPlaygroundFailed ?? 'Image generation failed';
  }

  Map<String, String>? get _resultHeaders {
    final headers = _result?['headers'];
    if (headers is! Map) return null;
    final result = <String, String>{};
    headers.forEach((key, value) {
      if (key is String && value is String && key.isNotEmpty) {
        result[key] = value;
      }
    });
    return result.isEmpty ? null : result;
  }

  String? get _resultUrl {
    final url = _result?['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  ConduitCardState get _state {
    if (_busy) return ConduitCardState.loading;
    if (_error != null) return ConduitCardState.error;
    if (_result != null) return ConduitCardState.success;
    return ConduitCardState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultUrl = _resultUrl;
    final providers = ref.watch(imageModelsProvider).value ?? const [];
    return ConduitActionCard(
      title: l10n?.createImage ?? 'Create image',
      subtitle: _error ?? _model,
      state: _state,
      maxWidth: 460,
      actions: [
        if (resultUrl != null && !_busy) ...[
          AdaptiveButton(
            key: const Key('image-card-upscale'),
            onPressed: _upscale,
            label: l10n?.imageCardUpscale ?? 'Upscale',
            style: AdaptiveButtonStyle.bordered,
            size: AdaptiveButtonSize.small,
          ),
          AdaptiveButton(
            key: const Key('image-card-edit'),
            onPressed: () => setState(() => _editing = !_editing),
            label: l10n?.imageCardEdit ?? 'Edit',
            style: AdaptiveButtonStyle.bordered,
            size: AdaptiveButtonSize.small,
          ),
        ],
        if (widget.onDismiss != null)
          AdaptiveButton(
            key: const Key('image-card-dismiss'),
            onPressed: widget.onDismiss,
            label: l10n?.cancel ?? 'Close',
            style: AdaptiveButtonStyle.plain,
            size: AdaptiveButtonSize.small,
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resultUrl != null) ...[
            EnhancedImageAttachment(
              key: const Key('image-card-result'),
              attachmentId: resultUrl,
              isMarkdownFormat: true,
              httpHeaders: _resultHeaders,
              constraints: const BoxConstraints(maxHeight: 320),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (providers.isNotEmpty) ...[
            Wrap(
              key: const Key('image-card-providers'),
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final provider in providers)
                  if (provider['id'] is String)
                    AdaptiveButton(
                      key: Key('image-card-provider-${provider['id']}'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _model = provider['id'] as String),
                      label: _providerName(provider),
                      style: _model == provider['id']
                          ? AdaptiveButtonStyle.filled
                          : AdaptiveButtonStyle.bordered,
                      size: AdaptiveButtonSize.small,
                    ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          Wrap(
            key: const Key('image-card-sizes'),
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              for (final entry in imageCardSizes.entries)
                AdaptiveButton(
                  key: Key('image-card-size-${entry.key}'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _size = entry.key),
                  label: entry.value,
                  style: _size == entry.key
                      ? AdaptiveButtonStyle.filled
                      : AdaptiveButtonStyle.bordered,
                  size: AdaptiveButtonSize.small,
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          AdaptiveTextField(
            key: const Key('image-card-prompt'),
            controller: _prompt,
            minLines: 2,
            maxLines: 4,
            placeholder:
                l10n?.imagesPlaygroundPrompt ?? 'Describe the image...',
          ),
          if (_editing) ...[
            const SizedBox(height: Spacing.sm),
            AdaptiveTextField(
              key: const Key('image-card-edit-prompt'),
              controller: _editPrompt,
              minLines: 1,
              maxLines: 3,
              placeholder:
                  l10n?.imagesPlaygroundEditPrompt ?? 'Describe the edit...',
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              AdaptiveButton(
                key: const Key('image-card-generate'),
                onPressed: _busy ? null : _generate,
                label: l10n?.imageCardGenerate ?? 'Generate',
                size: AdaptiveButtonSize.small,
              ),
              if (_editing) ...[
                const SizedBox(width: Spacing.sm),
                AdaptiveButton(
                  key: const Key('image-card-apply-edit'),
                  onPressed: _busy ? null : _applyEdit,
                  label: l10n?.imageCardApply ?? 'Apply',
                  style: AdaptiveButtonStyle.bordered,
                  size: AdaptiveButtonSize.small,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _providerName(Map<String, dynamic> provider) {
    final name = provider['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return (provider['id'] as String?) ?? '';
  }
}
