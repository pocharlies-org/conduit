import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';
import '../widgets/account_actions.dart';
import '../widgets/settings_page_scaffold.dart';

/// The saved Open WebUI accounts, grouped by server, a card for each server.
///
/// Tap an account to switch to it.
class ManageAccountsPage extends ConsumerWidget {
  const ManageAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final accounts = ref.watch(openWebUiAccountsProvider);

    return UtilityPageScaffold.settings(
      title: l10n.accountsTitle,
      children: [
        ...accounts.when(
          data: (entries) => _openWebUiCards(context, ref, entries),
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(Spacing.xl),
              child: Center(child: ConduitLoadingIndicator()),
            ),
          ],
          error: (_, _) => [
            InsetGroupedList(children: [UtilityRow(title: l10n.errorMessage)]),
            settingsSectionGap,
          ],
        ),
        // With one account, Settings' Sign out already signs out of it.
        if ((accounts.value?.length ?? 0) > 1) ...[
          settingsSectionGap,
          InsetGroupedList(
            children: [
              UtilityRow(
                key: const Key('accounts-sign-out-all'),
                title: l10n.accountsSignOutAll,
                leading: _RowGlyph(
                  UiUtils.platformIcon(
                    ios: CupertinoIcons.square_arrow_left,
                    android: Icons.logout,
                  ),
                  color: context.conduitTheme.error,
                ),
                destructive: true,
                onTap: () => signOutOfAllAccounts(context, ref),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _openWebUiCards(
    BuildContext context,
    WidgetRef ref,
    List<OpenWebUiAccountEntry> entries,
  ) {
    if (entries.isEmpty) return const [];
    final byServer = <String, List<OpenWebUiAccountEntry>>{};
    for (final entry in entries) {
      byServer.putIfAbsent(entry.server.id, () => []).add(entry);
    }
    return [
      for (final group in byServer.values) ...[
        InsetGroupedList(
          key: Key('accounts-server-${group.first.server.id}'),
          children: [
            UtilityRow(
              title: serverDisplayName(group.first.server),
              leading: _ServerBadge(
                name: serverDisplayName(group.first.server),
              ),
            ),
            for (final entry in group)
              SavedAccountRow(
                key: Key('accounts-row-${entry.id}'),
                entry: entry,
              ),
          ],
        ),
        settingsSectionGap,
      ],
    ];
  }
}

/// Up to two letters for a server, in a circle: the initials of the first
/// two words of its name, else the first letter of its host.
class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    return Container(
      width: IconSize.xl,
      height: IconSize.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.groupedBackground,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        maxLines: 1,
        style: AppTypography.labelSmallStyle.copyWith(
          color: theme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A card row's plain glyph, in a fixed box so every title lines up.
class _RowGlyph extends StatelessWidget {
  const _RowGlyph(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IconSize.xl,
      height: IconSize.xl,
      child: Icon(
        icon,
        color: color ?? context.conduitTheme.iconSecondary,
        size: IconSize.medium,
      ),
    );
  }
}
