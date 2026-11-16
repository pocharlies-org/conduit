import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/providers/app_providers.dart';

import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit_core/features/navigation/providers/sidebar_active_tab_provider.dart';

import '../widgets/sidebar_tab_registry.dart';

export 'sidebar_search_providers.dart';

export 'package:conduit_core/features/navigation/providers/sidebar_active_tab_provider.dart';
// The tablet width preference moved to conduit_core.
export 'package:conduit_core/features/navigation/providers/sidebar_tablet_width_provider.dart';

final sidebarNavigationSnapshotProvider = Provider<SidebarNavigationSnapshot>((
  ref,
) {
  final hasOpenWebUi = ref.watch(openWebUiAccountAvailableProvider);
  final availability = SidebarTabAvailability(
    hasOpenWebUi: hasOpenWebUi,
    notesEnabled: ref.watch(notesFeatureEnabledProvider),
    channelsEnabled: ref.watch(channelsFeatureEnabledProvider),
  );
  final tabs = visibleSidebarTabIds(availability);
  final persistedTab = ref.watch(sidebarActiveTabProvider);
  final legacyIndex = ref
      .read(sidebarActiveTabProvider.notifier)
      .pendingLegacyIndex();
  return SidebarNavigationSnapshot(
    tabs: tabs,
    isLegacySelection: legacyIndex != null,
    selectedTab: resolveSidebarTabSelection(
      persistedTab: persistedTab,
      legacyIndex: legacyIndex,
      visibleTabs: tabs,
    ),
  );
});
