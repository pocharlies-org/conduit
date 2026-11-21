import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:conduit/core/services/remote_file_download.dart';
import 'package:conduit/features/chat/services/native_image_viewer_bridge.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/utils/file_type_utils.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit_core/utils/file_link_utils.dart';

/// A link to a file the assistant generated (a spreadsheet, a deck, a photo):
/// a card that previews it in the app and hands it to another app.
///
/// PDFs keep their inline `PdfInlineView`; this covers what that view does not
/// render. Tapping fetches the bytes and shows them with the platform viewer
/// where it can (Quick Look on iOS renders xlsx, pptx, docx and images);
/// anywhere else, and for anything Quick Look refuses, the file goes straight
/// to the share sheet. The download button skips the preview and shares.
class FileLinkCard extends ConsumerStatefulWidget {
  const FileLinkCard({
    super.key,
    required this.url,
    this.label,
    this.constraints,
  });

  final String url;
  final String? label;
  final BoxConstraints? constraints;

  @override
  ConsumerState<FileLinkCard> createState() => _FileLinkCardState();
}

class _FileLinkCardState extends ConsumerState<FileLinkCard> {
  bool _busy = false;
  bool _failed = false;

  String _title(BuildContext context) => fileLinkTitle(
    rawLabel: widget.label,
    url: widget.url,
    fallback: AppLocalizations.of(context)?.document ?? 'Document',
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _fetch() => downloadServerFile(
    url: widget.url,
    container: ProviderScope.containerOf(context, listen: false),
    fileName: _title(context),
  );

  Future<void> _share(File file) => SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, name: file.path.split('/').last)]),
  );

  Future<void> _open() async {
    final file = await _fetch();
    final presented = await NativeImageViewerBridge.instance.present(
      files: [NativeImageFile(path: file.path, title: _title(context))],
      initialIndex: 0,
    );
    if (!presented) await _share(file);
  }

  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;
    final l10n = AppLocalizations.of(context);
    final title = _title(context);
    final extension = fileExtensionFromUrl(widget.url);
    final detail = _failed
        ? '${l10n?.error ?? 'Error'} · ${l10n?.retry ?? 'Retry'}'
        : extension.isEmpty
        ? (l10n?.download ?? 'Download')
        : extension.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Semantics(
        button: true,
        label: title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _run(_open),
          onLongPress: () => _run(() => _fetch().then(_share)),
          child: Container(
            constraints: widget.constraints ??
                const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: conduitTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppBorderRadius.md),
              border: Border.all(
                color: conduitTheme.textPrimary.withValues(alpha: 0.12),
                width: BorderWidth.regular,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FileTypeUtils.emojiForExtension(extension),
                  style: AppTypography.headlineLargeStyle,
                ),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelStyle.copyWith(
                          color: conduitTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        detail,
                        style: AppTypography.labelMediumStyle.copyWith(
                          color: _failed
                              ? conduitTheme.error
                              : conduitTheme.textSecondary.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                if (_busy)
                  const AdaptiveProgressIndicator.activity(radius: 9)
                else
                  AdaptiveButton(
                    onPressed: () => _run(() => _fetch().then(_share)),
                    label: l10n?.download ?? 'Download',
                    style: AdaptiveButtonStyle.bordered,
                    size: AdaptiveButtonSize.small,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
