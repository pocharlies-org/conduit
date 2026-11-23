import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:conduit_core/navigation/routes.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/utility_components.dart';

/// First-run screen letting a fresh install choose its chat backend.
///
/// OWU-134 left Open WebUI as the only backend, so this is the single entry
/// to the generic sign-in (OWU-157); the Hermes, Direct and Apple rows of the
/// upstream chooser went with those features.
class BackendChooserPage extends ConsumerWidget {
  const BackendChooserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;

    return UtilityPageScaffold.auth(
      title: l10n.backendChooserWelcome,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            child: Text(
              l10n.backendChooserPrompt,
              style: AppTypography.bodyMediumStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          InsetGroupedList(
            title: l10n.backendChooserSelfHostedSectionTitle,
            dividerIndent: _providerDividerIndent,
            children: [
              UtilitySelectionRow(
                leading: const _ProviderLogo(
                  assetName: 'assets/icons/open_webui.png',
                ),
                title: l10n.backendChooserOpenWebUITitle,
                subtitle: l10n.backendChooserOpenWebUISubtitle,
                selected: false,
                showSelectionIndicator: false,
                trailing: _chooserChevron(context),
                onTap: () => context.go(Routes.serverConnection),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _chooserChevron(BuildContext context) => Icon(
  context.usesCupertinoChrome
      ? CupertinoIcons.chevron_forward
      : Icons.chevron_right,
  color: context.conduitTheme.iconSecondary,
  size: IconSize.small,
);

/// Matches the 40x40 icon-badge footprint used by `SettingsIconBadge` and the
/// Cupertino leading slot in `UtilitySelectionRow`; a larger box gets squeezed
/// into 40 there, which crops the edges off a full-bleed logo.
const double _providerLogoSize = 40;
const double _providerDividerIndent =
    Spacing.md + _providerLogoSize + Spacing.sm + Spacing.xs;

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Image.asset(
        assetName,
        width: _providerLogoSize,
        height: _providerLogoSize,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
