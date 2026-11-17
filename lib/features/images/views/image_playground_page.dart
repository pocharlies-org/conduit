import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/features/chat/services/image_viewer_files.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/utility_components.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Open WebUI's Images playground: create an image from a prompt, or pick
/// source images and describe the change. Results stay in the page until the
/// user shares them, which is how the web keeps its own in-memory grid.
class ImagePlaygroundPage extends ConsumerWidget {
  const ImagePlaygroundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (!ref.watch(imageGenerationAvailableProvider)) {
      return UtilityPageScaffold.settings(
        key: const Key('image-playground-unavailable'),
        title: l10n.imagesPlaygroundTitle,
        children: [Text(l10n.imagesPlaygroundUnavailable)],
      );
    }
    return const _ImagePlayground();
  }
}

class _PickedImage {
  const _PickedImage(this.bytes, this.type);

  final Uint8List bytes;
  final ImageFileType type;

  String get dataUrl => 'data:${type.mimeType};base64,${base64Encode(bytes)}';
}

class _ResultImage {
  const _ResultImage(this.bytes, this.type);

  final Uint8List bytes;
  final ImageFileType type;
}

class _ImagePlayground extends ConsumerStatefulWidget {
  const _ImagePlayground();

  @override
  ConsumerState<_ImagePlayground> createState() => _ImagePlaygroundState();
}

class _ImagePlaygroundState extends ConsumerState<_ImagePlayground> {
  final TextEditingController _prompt = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<_PickedImage> _sources = [];
  final List<_ResultImage> _results = [];
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickSources() async {
    try {
      final files = await _picker.pickMultiImage();
      final picked = <_PickedImage>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        picked.add(
          _PickedImage(bytes, detectImageFileType(bytes, contentType: file.mimeType)),
        );
      }
      if (!mounted || picked.isEmpty) return;
      setState(() => _sources.addAll(picked));
    } catch (_) {
      _snack(AppLocalizations.of(context)!.imagesPlaygroundPickFailed);
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      _snack(l10n.imagesPlaygroundPromptRequired);
      return;
    }
    final api = ref.read(apiServiceProvider);
    if (api == null) {
      _snack(l10n.imagesPlaygroundFailed);
      return;
    }
    setState(() => _busy = true);
    try {
      final files = _sources.isEmpty
          ? await api.generateImage(prompt: prompt)
          : await api.editImage(
              images: [for (final source in _sources) source.dataUrl],
              prompt: prompt,
            );
      final results = <_ResultImage>[];
      for (final file in files) {
        final id = file['id'];
        if (id is! String || id.isEmpty) continue;
        results.add(_decode(await api.getFileContent(id)));
      }
      if (!mounted) return;
      setState(() => _results.insertAll(0, results));
    } catch (error) {
      if (mounted) _snack(_describe(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The file endpoint answers with a `data:` URL for images.
  _ResultImage _decode(String content) {
    final comma = content.indexOf(',');
    if (!content.startsWith('data:') || comma < 0) {
      throw const FormatException('Expected an image data URL');
    }
    final bytes = base64Decode(content.substring(comma + 1));
    return _ResultImage(
      bytes,
      detectImageFileType(bytes, contentType: content.substring(0, comma)),
    );
  }

  String _describe(Object error, AppLocalizations l10n) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    }
    return l10n.imagesPlaygroundFailed;
  }

  Future<void> _share(_ResultImage image) async {
    Directory? directory;
    try {
      directory = await createImageSessionDirectory('share');
      final file = await writeImageFile(
        image.bytes,
        directory: directory,
        baseName: 'conduit_image',
        type: image.type,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: image.type.mimeType)],
        ),
      );
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context)!.imagesPlaygroundFailed);
    } finally {
      // The share target may read the file after share() returns.
      if (directory != null) releaseImageSessionDirectory(directory);
    }
  }

  void _snack(String message) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = context.conduitTheme;
    final editing = _sources.isNotEmpty;

    return UtilityPageScaffold.settings(
      title: l10n.imagesPlaygroundTitle,
      children: [
        Text(
          l10n.imagesPlaygroundHint,
          style: AppTypography.bodySmallStyle.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (editing)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (var i = 0; i < _sources.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Spacing.sm),
                        child: Image.memory(
                          _sources[i].bytes,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          key: Key('image-playground-source-$i'),
                          onTap: () => setState(() => _sources.removeAt(i)),
                          child: ConduitIconButton(
                            icon: Icons.close,
                            isCompact: true,
                            iconColor: tokens.neutralOnSurface,
                            tooltip: l10n.imagesPlaygroundRemoveSource,
                            onPressed: () => setState(() => _sources.removeAt(i)),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        AdaptiveTextField(
          key: const Key('image-playground-prompt'),
          controller: _prompt,
          minLines: 2,
          maxLines: 5,
          placeholder: editing
              ? l10n.imagesPlaygroundEditPrompt
              : l10n.imagesPlaygroundPrompt,
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _pickSources,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(l10n.imagesPlaygroundAddImage),
            ),
            const Spacer(),
            ConduitButton(
              key: const Key('image-playground-run'),
              text: _busy
                  ? l10n.imagesPlaygroundRunning
                  : l10n.imagesPlaygroundRun,
              isLoading: _busy,
              onPressed: _busy ? null : _run,
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Text(
              l10n.imagesPlaygroundEmpty,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStyle.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
              mainAxisSpacing: Spacing.sm,
              crossAxisSpacing: Spacing.sm,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) => GestureDetector(
              key: Key('image-playground-result-$index'),
              onTap: () => _share(_results[index]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Spacing.sm),
                child: Image.memory(
                  _results[index].bytes,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}