import 'package:conduit/shared/widgets/platform_ui/vocabulary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/persistence/persistence_keys.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/utility_components.dart';

/// Asistente del primer arranque (OWU-105): elige la cuenta configurada desde
/// fuera del teléfono y entra; completarlo no vuelve a salir. Los arranques
/// siguientes usan la entrada automática de OWU-104.
class SetupWizardPage extends ConsumerWidget {
  const SetupWizardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final configs = ref.watch(serverConfigsProvider);
    return UtilityPageScaffold.auth(
      title: l10n.setupWizardTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(l10n.setupWizardSubtitle),
          const SizedBox(height: 16),
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
    // OWU-106: elegir cuenta aquí es elegir Open WebUI; el arranque no puede
    // quedarse en otro backend por un valor viejo.
    await ref.read(preferredBackendProvider.notifier).set(PreferredBackend.owui);
    await PreferencesStore.put(PreferenceKeys.setupWizardCompleted, true);
    setupWizardPending = false;
    ref.invalidate(serverConfigsProvider);
    ref.invalidate(activeServerProvider);
    if (context.mounted) context.go(Routes.splash);
  }
}