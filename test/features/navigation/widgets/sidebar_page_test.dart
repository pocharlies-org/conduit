import 'dart:ui' show Tristate;

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:checks/checks.dart';
import 'package:conduit_core/models/conversation.dart';
import 'package:conduit/shared/services/navigation_service.dart';
import 'package:conduit_core/sync/sync_engine.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit/features/navigation/widgets/sidebar_page.dart';
import 'package:conduit/features/navigation/widgets/sidebar_user_pill.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sidebar_page_test_support.dart';

void main() {
  test('Mac windows do not reserve the iPad window-control inset', () {
    expect(
      resolveSidebarWindowedLeadingInset(
        usesNativeIOS26Chrome: true,
        isWindowed: true,
        isIOSAppOnMac: true,
      ),
      0,
    );
    expect(
      resolveSidebarWindowedLeadingInset(
        usesNativeIOS26Chrome: true,
        isWindowed: true,
        isIOSAppOnMac: false,
      ),
      62,
    );
  });

  testWidgets('native glass profile avatar uses one compact native button', (
    tester,
  ) async {
    var presses = 0;
    const profileButtonKey = ValueKey<String>('sidebar-profile-button');

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: buildSidebarProfileButton(
            supportsNativeGlass: true,
            onPressed: () => presses++,
            fallbackStyle: AdaptiveButtonStyle.glass,
            child: const SizedBox.square(dimension: 36),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CupertinoButton), findsNothing);
    expect(find.byType(CNButton), findsOneWidget);
    expect(find.byType(AdaptiveButton), findsNothing);
    expect(tester.getSize(find.byKey(profileButtonKey)), const Size(44, 44));
    await tester.tap(find.byKey(profileButtonKey));
    expect(presses, 1);

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: buildSidebarProfileButton(
            supportsNativeGlass: false,
            onPressed: () {},
            fallbackStyle: AdaptiveButtonStyle.plain,
            child: const SizedBox.square(dimension: 36),
          ),
        ),
      ),
    );

    expect(find.byType(AdaptiveButton), findsOneWidget);
  });

  test('native profile glass reuses cached avatar bytes', () {
    final bytes = Uint8List.fromList(const [1, 2, 3]);
    final target = buildSidebarProfileButton(
      supportsNativeGlass: true,
      onPressed: () {},
      fallbackStyle: AdaptiveButtonStyle.glass,
      nativeAvatarBytes: bytes,
      child: const SizedBox.square(dimension: 36),
    ) as SizedBox;
    final button = target.child! as CNButton;
    final placeholderTarget = buildSidebarProfileButton(
      supportsNativeGlass: true,
      onPressed: () {},
      fallbackStyle: AdaptiveButtonStyle.glass,
      child: const SizedBox.square(dimension: 36),
    ) as SizedBox;
    final placeholderButton = placeholderTarget.child! as CNButton;

    expect(identical(button.imageAsset?.imageData, bytes), isTrue);
    expect(button.imageAsset?.assetPath, isEmpty);
    expect(button.imageAsset?.size, 28);
    expect(button.config.minHeight, TouchTarget.minimum);
    expect(button.config.width, TouchTarget.minimum);
    expect(button.config.style, CNButtonStyle.glass);
    expect(button.key, isNot(placeholderButton.key));
  });

  test('accountless native fallback targets generic settings', () {
    expect(
      sidebarProfileFallbackRouteName(hasOpenWebUiUser: false),
      RouteNames.profile,
    );
    expect(
      sidebarProfileFallbackRouteName(hasOpenWebUiUser: true),
      RouteNames.profile,
    );
  });

  testWidgets(
    'renders without TabBarView and shows chats as active by default',
    (tester) async {
      final controllers = SidebarTestSidebarHarnessControllers();

      await tester.pumpWidget(
        sidebarTestBuildHarness(controllers: controllers),
      );

      expect(find.byType(TabBarView), findsNothing);

      final chatsLayer = tester.widget<Opacity>(
        sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.chats),
      );

      expect(chatsLayer.opacity, 1);
    },
  );

  testWidgets('shows determinate sync progress above every sidebar tab', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();

    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        syncStatus: const SyncStatus(
          phase: SyncPhase.running,
          stage: SyncStage.chats,
          completedItems: 3,
          totalItems: 8,
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey<String>('sidebar-sync-progress')),
    );
    check(progress.value).isNotNull().equals(3 / 8);
    check(progress.semanticsLabel).equals('Syncing chats');
    check(progress.semanticsValue).equals('38%');

    await tester.tap(sidebarTestBottomNavTabLabel('Notes'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('sidebar-sync-progress')),
      findsOneWidget,
    );
  });

  testWidgets('hides sidebar sync progress while idle', (tester) async {
    final controllers = SidebarTestSidebarHarnessControllers();

    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        syncStatus: const SyncStatus(),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('sidebar-sync-progress')),
      findsNothing,
    );
  });

  testWidgets('retained API after logout hides OpenWebUI-only tabs', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();

    await tester.pumpWidget(
      sidebarTestBuildHarness(controllers: controllers, isAuthenticated: false),
    );
    await tester.pump();

    expect(sidebarTestBottomNavTabLabel('Notes'), findsNothing);
    expect(sidebarTestBottomNavTabLabel('Channels'), findsNothing);
  });

  testWidgets(
    'persisted Notes identity restores notes when notes are enabled',
    (tester) async {
      final controllers = SidebarTestSidebarHarnessControllers(
        initialTab: SidebarTabId.notes,
      );

      await tester.pumpWidget(
        sidebarTestBuildHarness(controllers: controllers),
      );

      final notesLayer = tester.widget<Opacity>(
        sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.notes),
      );
      final chatsLayer = tester.widget<Opacity>(
        sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.chats),
      );

      expect(notesLayer.opacity, 1);
      expect(chatsLayer.opacity, 0);
    },
  );

  testWidgets('reselecting a legacy tab persists its stable identity', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers(legacyIndex: 1);

    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    final notesLayer = tester.widget<Opacity>(
      sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.notes),
    );
    check(notesLayer.opacity).equals(1);

    await tester.tap(sidebarTestBottomNavTabLabel('Notes'));
    await tester.pump();

    check(controllers.activeTabNotifier.currentValue)
        .equals(SidebarTabId.notes);
    check(controllers.activeTabNotifier.pendingLegacyIndex()).isNull();
  });

  testWidgets(
    'unavailable persisted tab falls back without changing its identity',
    (tester) async {
      final controllers = SidebarTestSidebarHarnessControllers(
        notesEnabled: false,
        initialTab: SidebarTabId.notes,
      );

      await tester.pumpWidget(
        sidebarTestBuildHarness(controllers: controllers),
      );

      final chatsLayer = tester.widget<Opacity>(
        sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.chats),
      );

      expect(chatsLayer.opacity, 1);
      expect(sidebarTestBottomNavTabLabel('Notes'), findsNothing);
      expect(controllers.activeTabNotifier.currentValue, SidebarTabId.notes);
    },
  );

  testWidgets('active optional tab restores when its feature returns', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers(
      initialTab: SidebarTabId.notes,
    );

    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    controllers.notesNotifier.setEnabled(false);
    await tester.pump();

    final chatsLayer = tester.widget<Opacity>(
      sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.chats),
    );

    expect(chatsLayer.opacity, 1);
    expect(controllers.activeTabNotifier.currentValue, SidebarTabId.notes);
    expect(sidebarTestBottomNavTabLabel('Notes'), findsNothing);

    controllers.notesNotifier.setEnabled(true);
    await tester.pump();

    final notesLayer = tester.widget<Opacity>(
      sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.notes),
    );
    expect(notesLayer.opacity, 1);
  });

  testWidgets('inactive layers are excluded from focus and semantics', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();

    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    final activeFocus = tester.widget<ExcludeFocus>(
      find
          .descendant(
            of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.chats),
            matching: find.byType(ExcludeFocus),
          )
          .first,
    );
    final inactiveFocus = tester.widget<ExcludeFocus>(
      find
          .descendant(
            of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.notes),
            matching: find.byType(ExcludeFocus),
          )
          .first,
    );
    final activeSemantics = tester.widget<ExcludeSemantics>(
      find
          .descendant(
            of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.chats),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    );
    final inactiveSemantics = tester.widget<ExcludeSemantics>(
      find
          .descendant(
            of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.notes),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    );

    expect(activeFocus.excluding, isFalse);
    expect(inactiveFocus.excluding, isTrue);
    expect(activeSemantics.excluding, isFalse);
    expect(inactiveSemantics.excluding, isTrue);
  });

  testWidgets('renders adaptive bottom tab bar instead of TabBar', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.height, 56);
    expect(
      navigationBar.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
    );
    expect(sidebarTestBottomNavTabLabel('Chats'), findsOneWidget);
    expect(sidebarTestBottomNavTabLabel('Notes'), findsOneWidget);
    expect(sidebarTestBottomNavTabLabel('Channels'), findsOneWidget);
  });

  testWidgets('reselecting a tab uses a static scroll under reduced motion', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    final timestamp = DateTime(2026, 1, 1);
    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        disableAnimations: true,
        conversations: List<Conversation>.generate(
          30,
          (index) => Conversation(
            id: 'reduced-motion-$index',
            title: 'Conversation $index',
            createdAt: timestamp,
            updatedAt: timestamp,
            messages: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chatsScroll = find.byKey(
      const PageStorageKey<String>('chats_drawer_scroll'),
    );
    final controller = tester.widget<CustomScrollView>(chatsScroll).controller!;
    await tester.drag(chatsScroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));

    await tester.tap(sidebarTestBottomNavTabLabel('Chats'));
    await tester.pump();

    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persistent tablet uses bottom navigation with every tab', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        persistentTabletSidebar: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sidebar-tablet-navigation')),
      findsNothing,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(NavigationBar)).width,
      tester
          .getSize(find.byKey(const ValueKey<String>('sidebar-page-surface')))
          .width,
    );
    for (final label in ['Chats', 'Notes', 'Channels']) {
      expect(sidebarTestBottomNavTabLabel(label), findsOneWidget);
    }

    await tester.tap(sidebarTestBottomNavTabLabel('Notes'));
    await tester.pumpAndSettle();

    expect(controllers.activeTabNotifier.currentValue, SidebarTabId.notes);
    expect(
      find.descendant(
        of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.notes),
        matching: find.byWidgetPredicate(
          (widget) => widget is ExcludeSemantics && !widget.excluding,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(sidebarTestBottomNavTabLabel('Channels'));
    await tester.pumpAndSettle();

    expect(controllers.activeTabNotifier.currentValue, SidebarTabId.channels);
    expect(
      find.descendant(
        of: sidebarTestLayerRootFinder(SidebarTestSidebarTabLayer.channels),
        matching: find.byWidgetPredicate(
          (widget) => widget is ExcludeSemantics && !widget.excluding,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('persistent iOS 26 sidebar requests a full-width native bar', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    addTearDown(PlatformUiCapabilities.resetDebugOverrides);

    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        persistentTabletSidebar: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CNTabBar), findsNothing);
    final tabBar = tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar));
    expect(tabBar.items, hasLength(3));
    expect(
      tester.getSize(find.byType(CupertinoTabBar)).width,
      tester.getSize(find.byType(SidebarPage)).width,
    );
  });

  testWidgets('iOS 26 native overlay keeps the tab labels', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    addTearDown(PlatformUiCapabilities.resetDebugOverrides);

    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));
    await tester.pump(const Duration(milliseconds: 500));

    final tabBar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(tabBar.items, hasLength(3));
    expect(tabBar.iconSize, isNull);
    expect(tabBar.items.map((item) => item.label), [
      'Chats',
      'Notes',
      'Channels',
    ]);
    for (final item in tabBar.items) {
      expect(item.icon?.size, kCupertinoNativeControlSymbolExtent);
    }
  });

  testWidgets('persistent tablet navigation remains usable at 2x text', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        persistentTabletSidebar: true,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('sidebar-tablet-navigation')),
      findsNothing,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(sidebarTestBottomNavTabLabel('Notes'));
    await tester.pumpAndSettle();
    expect(controllers.activeTabNotifier.currentValue, SidebarTabId.notes);
  });

  testWidgets('channel helpers align with the channels tab', (tester) async {
    final controllers = SidebarTestSidebarHarnessControllers(
      initialTab: SidebarTabId.channels,
    );
    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));
    await tester.pumpAndSettle();

    expect(sidebarTestBottomNavTabLabel('Channels'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    final context = tester.element(find.byType(SidebarPage));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.searchChannels), findsOneWidget);
    expect(find.text(l10n.searchFiles), findsNothing);
  });

  testWidgets('adaptive bottom bar tapping switches active tab', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    await tester.tap(sidebarTestBottomNavTabLabel('Channels'));
    await tester.pumpAndSettle();

    final channelsLayer = tester.widget<Opacity>(
      sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.channels),
    );
    expect(channelsLayer.opacity, 1);

    final chatsLayer = tester.widget<Opacity>(
      sidebarTestLayerOpacityFinder(SidebarTestSidebarTabLayer.chats),
    );
    expect(chatsLayer.opacity, 0);
  });

  testWidgets('adaptive bottom bar provides tab semantics', (tester) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    await tester.pumpWidget(sidebarTestBuildHarness(controllers: controllers));

    final barScope = find.byType(NavigationBar);

    final chatsSemantics = tester.getSemantics(
      find.descendant(of: barScope, matching: find.text('Chats')).first,
    );
    expect(
      chatsSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );

    final channelsSemantics = tester.getSemantics(
      find.descendant(of: barScope, matching: find.text('Channels')).first,
    );
    expect(
      channelsSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
  });
}
