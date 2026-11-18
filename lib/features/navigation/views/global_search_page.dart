import 'dart:async';

import 'package:conduit_core/models/workspace_search.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/services/navigation_service.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/conversation_selection_provider.dart';
import '../providers/workspace_search_providers.dart';

/// The global search the web's own search panel offers: `GET /api/v1/search`
/// over chats, channel messages and notes, grouped by kind, with the kind
/// filters the server accepts.
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(workspaceSearchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(workspaceSearchQueryProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(workspaceSearchFilterProvider);
    final results = ref.watch(workspaceSearchResultsProvider);

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: l10n.searchEverything,
        leading: ConduitIconButton(
          icon: CupertinoIcons.back,
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AdaptiveTextField(
                controller: _controller,
                autofocus: true,
                placeholder: l10n.searchEverythingHint,
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  color: context.conduitTheme.iconSecondary,
                  size: IconSize.small,
                ),
                onChanged: _onChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  ref.read(workspaceSearchQueryProvider.notifier).set(value);
                },
              ),
            ),
            const SizedBox(height: Spacing.sm),
            _SearchKindFilters(
              filter: filter,
              results: results.asData?.value,
              onSelected: (kind) =>
                  ref.read(workspaceSearchFilterProvider.notifier).set(kind),
            ),
            Expanded(
              child: results.when(
                data: (page) => _SearchResultsBody(
                  page: page,
                  filter: filter,
                  onOpen: _openHit,
                ),
                loading: () => const Center(child: ConduitLoadingIndicator()),
                error: (error, _) => _SearchError(
                  onRetry: () =>
                      ref.invalidate(workspaceSearchResultsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openHit(WorkspaceSearchHit hit) async {
    final l10n = AppLocalizations.of(context)!;
    switch (hit.kind) {
      case WorkspaceSearchKind.note:
        await NavigationService.router.push('/notes/${hit.id}');
      case WorkspaceSearchKind.message:
        final channelId = hit.channelId;
        if (channelId == null) return;
        await NavigationService.router.push('/channel/$channelId');
      case WorkspaceSearchKind.chat:
        // A shared snapshot (`/s/<id>`) is not a live chat the list can open.
        if (hit.isSnapshot) {
          AdaptiveSnackBar.show(context, message: l10n.searchSharedSnapshot);
          return;
        }
        final api = ref.read(apiServiceProvider);
        if (api == null) return;
        final conversation = await api.getConversation(hit.id);
        if (!mounted) return;
        final result = await ref
            .read(conversationSelectionProvider.notifier)
            .select(conversation);
        if (!mounted) return;
        if (result.disposition == ConversationSelectionDisposition.committed) {
          NavigationService.router.go(Routes.chat);
        }
    }
  }
}

class _SearchKindFilters extends StatelessWidget {
  const _SearchKindFilters({
    required this.filter,
    required this.results,
    required this.onSelected,
  });

  final WorkspaceSearchKind? filter;
  final WorkspaceSearchResults? results;
  final ValueChanged<WorkspaceSearchKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final kinds = results?.kinds ?? WorkspaceSearchKind.values;
    final entries = <(WorkspaceSearchKind?, String)>[
      (null, l10n.searchFilterAll),
      for (final kind in kinds) (kind, _kindLabel(l10n, kind)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          for (final (kind, label) in entries)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.xs),
              child: AdaptiveChip.filter(
                label: Text(label),
                selected: filter == kind,
                onSelected: (on) => onSelected(on ? kind : null),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({
    required this.page,
    required this.filter,
    required this.onOpen,
  });

  final WorkspaceSearchResults? page;
  final WorkspaceSearchKind? filter;
  final ValueChanged<WorkspaceSearchHit> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (page == null) {
      return ConduitEmptyState(
        icon: CupertinoIcons.search,
        title: l10n.searchEverything,
        message: l10n.searchEverythingHint,
        isCompact: true,
      );
    }
    final visible = filter == null ? page!.hits : page!.of(filter!);
    if (visible.isEmpty) {
      return ConduitEmptyState(
        icon: CupertinoIcons.search,
        title: l10n.searchNoResults,
        message: '',
        isCompact: true,
      );
    }
    final groups = <WorkspaceSearchKind, List<WorkspaceSearchHit>>{
      for (final kind in WorkspaceSearchKind.values)
        if (visible.where((hit) => hit.kind == kind).toList()
            case final hits when hits.isNotEmpty)
          kind: hits,
    };
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      children: [
        for (final entry in groups.entries) ...[
          ConduitSectionHeader(title: _kindLabel(l10n, entry.key)),
          for (final hit in entry.value)
            AdaptiveListTile(
              leading: Icon(
                _kindIcon(entry.key),
                color: context.conduitTheme.iconSecondary,
                size: IconSize.small,
              ),
              title: Text(
                hit.title.isEmpty ? l10n.searchUntitled : hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                hit.snippet.isEmpty ? hit.context : hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpen(hit),
            ),
        ],
      ],
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConduitEmptyState(
      icon: CupertinoIcons.exclamationmark_circle,
      title: l10n.searchFailedTitle,
      message: l10n.searchFailedMessage,
      action: ConduitButton(
        text: l10n.retry,
        onPressed: onRetry,
      ),
      isCompact: true,
    );
  }
}

String _kindLabel(AppLocalizations l10n, WorkspaceSearchKind kind) =>
    switch (kind) {
      WorkspaceSearchKind.chat => l10n.searchKindChats,
      WorkspaceSearchKind.message => l10n.searchKindMessages,
      WorkspaceSearchKind.note => l10n.searchKindNotes,
    };

IconData _kindIcon(WorkspaceSearchKind kind) => switch (kind) {
  WorkspaceSearchKind.chat => CupertinoIcons.chat_bubble,
  WorkspaceSearchKind.message => CupertinoIcons.bubble_left,
  WorkspaceSearchKind.note => CupertinoIcons.doc_text,
};