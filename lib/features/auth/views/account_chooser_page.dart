import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';

import '../../../l10n/app_localizations.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: configs.maybeWhen(
              data: (list) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l10n.accountChooserTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  for (final config in list)
                    UtilitySelectionRow(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: config.name.isEmpty ? config.url : config.name,
                      subtitle: config.url,
                      selected: config.isActive,
                      onTap: () => _choose(context, ref, config.id),
                    ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ),
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
