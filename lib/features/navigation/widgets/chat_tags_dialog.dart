import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/utils/debug_logger.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/themed_dialogs.dart';

import '../providers/sidebar_tag_providers.dart';

/// Edits a chat's tags the way the web's `Tags.svelte` does: the chat's own
/// tags can be removed, every tag the account has is offered as a suggestion,
/// and a new one can be typed. The server is the source of truth for the
/// resulting list, so each call's answer replaces the local one.
Future<void> showChatTagsDialog(
  BuildContext context, {
  required String chatId,
  required List<String> tags,
}) {
  return ThemedDialogs.showCustom<void>(
    context: context,
    builder: (context) => _ChatTagsDialog(chatId: chatId, tags: tags),
  );
}

class _ChatTagsDialog extends ConsumerStatefulWidget {
  const _ChatTagsDialog({required this.chatId, required this.tags});

  final String chatId;
  final List<String> tags;

  @override
  ConsumerState<_ChatTagsDialog> createState() => _ChatTagsDialogState();
}

class _ChatTagsDialogState extends ConsumerState<_ChatTagsDialog> {
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

    return AlertDialog(
      title: Text(l10n.chatTagsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    InputChip(
                      label: Text(tag),
                      onDeleted: _busy ? null : () => _remove(tag),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _controller,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.chatTagHint,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.add,
                  onPressed: _busy ? null : () => _add(_controller.text),
                ),
              ),
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
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final tag in offered)
                    ActionChip(
                      label: Text(tag),
                      onPressed: _busy ? null : () => _add(tag),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}