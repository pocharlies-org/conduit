import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/utility_components.dart';

/// Selector de cuenta del arranque frío (OWU-104): con más de una cuenta
/// configurada, elige con cuál entrar antes de que auth decida. Con una sola
/// la app entra directa y esta pantalla no aparece.
class AccountChooserPage extends ConsumerWidget {
  const AccountChooserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final configs = ref.watch(serverConfigsProvider);
    return UtilityPageScaffold.auth(
      title: l10n.accountChooserTitle,
      body: Column(
        children: [
          for (final config in configs.value ?? const <ServerConfig>[])
            UtilitySelectionRow(
              leading: Icon(
                UiUtils.platformIcon(
                  ios: CupertinoIcons.person_crop_circle,
                  android: Icons.account_circle_outlined,
                ),
              ),
              title: config.name.isEmpty ? config.url : config.name,
              subtitle: config.url,
              selected: config.isActive,
              onTap: () => _choose(context, ref, config.id),
            ),
        ],
      ),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    String serverId,
  ) async {
    final storage = ref.read(optimizedStorageServiceProvider);
    await storage.setActiveServerId(serverId);
    accountChooserPending = false;
    ref.invalidate(serverConfigsProvider);
    ref.invalidate(activeServerProvider);
    if (context.mounted) context.go(Routes.splash);
  }
}
