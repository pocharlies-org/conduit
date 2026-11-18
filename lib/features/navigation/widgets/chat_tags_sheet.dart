import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/utils/debug_logger.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/sheet_handle.dart';
import 'package:conduit/shared/widgets/themed_dialogs.dart';
import 'package:conduit/shared/widgets/themed_sheets.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sidebar_tag_providers.dart';

/// Edits a chat's tags the way the web's `Tags.svelte` does: the chat's own
/// tags can be removed, every tag the account has is offered as a suggestion,
/// and a new one can be typed. The server is the source of truth for the
/// resulting list, so each call's answer replaces the local one.
Future<void> showChatTagsSheet(
  BuildContext context, {
  required String chatId,
  required List<String> tags,
}) {
  return ThemedSheets.showCustom<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ChatTagsSheet(chatId: chatId, tags: tags),
  );
}

class _ChatTagsSheet extends ConsumerStatefulWidget {
  const _ChatTagsSheet({required this.chatId, required this.tags});

  final String chatId;
  final List<String> tags;

  @override
  ConsumerState<_ChatTagsSheet> createState() => _ChatTagsSheetState();
}

class _ChatTagsSheetState extends ConsumerState<_ChatTagsSheet> {
  late List<String> _tags = widget.tags;
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(Future<List<Map<String, dynamic>>> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await call();
      if (!mounted) return;
      final names = <String>[
        for (final tag in saved)
          if (tag['name'] case final String name when name.isNotEmpty) name,
      ]..sort();
      setState(() => _tags = names);
      ref
          .read(conversationsProvider.notifier)
          .updateConversationFromRemote(
            widget.chatId,
            (conversation) => conversation.copyWith(tags: names),
          );
      ref.invalidate(chatTagNamesProvider);
    } catch (error, stackTrace) {
      DebugLogger.error(
        'chat-tags-failed',
        scope: 'chat/tags',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) await _showError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _tags.contains(trimmed)) return;
    final api = ref.read(apiServiceProvider);
    if (api == null) return;
    await _apply(() => api.addChatTag(widget.chatId, trimmed));
    if (mounted) _controller.clear();
  }

  Future<void> _remove(String name) async {
    final api = ref.read(apiServiceProvider);
    if (api == null) return;
    await _apply(() => api.removeChatTag(widget.chatId, name));
  }

  Future<void> _showError() async {
    final l10n = AppLocalizations.of(context)!;
    await ThemedDialogs.confirm(
      context,
      title: l10n.error,
      message: l10n.failedToSaveChatTags,
      confirmText: l10n.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;
    final suggestions = ref
        .watch(chatTagNamesProvider)
        .maybeWhen(data: (names) => names, orElse: () => const <String>[]);
    final offered = suggestions.where((name) => !_tags.contains(name)).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.xl),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Icon(
                  CupertinoIcons.tag,
                  color: theme.iconPrimary,
                  size: IconSize.lg,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    l10n.chatTagsTitle,
                    style: AppTypography.headlineSmallStyle.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (_tags.isEmpty)
              Text(
                l10n.chatTagsEmpty,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final tag in _tags)
                    ConduitChip(
                      label: tag,
                      isSelected: true,
                      icon: CupertinoIcons.xmark,
                      onTap: _busy ? null : () => _remove(tag),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.sm),
            ConduitInput(
              controller: _controller,
              enabled: !_busy,
              hint: l10n.chatTagHint,
              textInputAction: TextInputAction.done,
              onSubmitted: _busy ? null : _add,
            ),
            if (offered.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.chatTagSuggestions,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final tag in offered)
                    ConduitChip(
                      label: tag,
                      onTap: _busy ? null : () => _add(tag),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.md),
            ConduitTextButton(
              text: l10n.close,
              onPressed: () => Navigator.of(context).maybePop(),
              isPrimary: true,
            ),
          ],
        ),
      ),
    );
  }
}