import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../channels/widgets/channel_list_tab.dart';
import '../../notes/widgets/notes_list_tab.dart';
import '../controllers/sidebar_tab_behavior.dart';

import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';

import '../utils/sidebar_create_action.dart';
import 'chats_drawer.dart';

typedef SidebarTabLabelBuilder = String Function(AppLocalizations l10n);
typedef SidebarTabBodyBuilder = Widget Function({
  required bool showBottomNavigation,
  required bool active,
});
typedef SidebarTabVisibilityPredicate = bool Function(
  SidebarTabAvailability availability,
);

/// Canonical visibility, presentation, and behavior for a sidebar destination.
@immutable
final class SidebarTabDescriptor {
  const SidebarTabDescriptor({
    required this.id,
    required this.labelBuilder,
    required this.searchHintBuilder,
    required this.bodyBuilder,
    required this.materialIcon,
    required this.selectedMaterialIcon,
    required this.sfSymbol,
    required this.selectedSfSymbol,
    required this.isVisible,
    this.createAction,
    this.behavior = standardSidebarTabBehavior,
  });

  final SidebarTabId id;
  final SidebarTabLabelBuilder labelBuilder;
  final SidebarTabLabelBuilder searchHintBuilder;
  final SidebarTabBodyBuilder bodyBuilder;
  final IconData materialIcon;
  final IconData selectedMaterialIcon;
  final String sfSymbol;
  final String selectedSfSymbol;
  final SidebarTabVisibilityPredicate isVisible;
  final SidebarCreateAction? createAction;
  final SidebarTabBehavior behavior;

  String label(AppLocalizations l10n) => labelBuilder(l10n);
  String searchHint(AppLocalizations l10n) => searchHintBuilder(l10n);

  ValueKey<String> get layerKey =>
      ValueKey<String>('sidebar-tab-layer-${id.name}');
}

String _chatsLabel(AppLocalizations l10n) => l10n.sidebarChatsTab;
String _notesLabel(AppLocalizations l10n) => l10n.sidebarNotesTab;
String _channelsLabel(AppLocalizations l10n) => l10n.sidebarChannelsTab;
String _conversationSearchHint(AppLocalizations l10n) =>
    l10n.searchConversations;
String _notesSearchHint(AppLocalizations l10n) => l10n.searchNotes;
String _channelsSearchHint(AppLocalizations l10n) => l10n.searchChannels;

Widget _chatsBody({required bool showBottomNavigation, required bool active}) =>
    const ChatsDrawer();

Widget _notesBody({required bool showBottomNavigation, required bool active}) =>
    const NotesListTab();

Widget _channelsBody({
  required bool showBottomNavigation,
  required bool active,
}) => const ChannelListTab();

bool _chatsVisible(SidebarTabAvailability availability) => true;

bool _notesVisible(SidebarTabAvailability availability) =>
    availability.hasOpenWebUi && availability.notesEnabled;

bool _channelsVisible(SidebarTabAvailability availability) =>
    availability.hasOpenWebUi && availability.channelsEnabled;

const sidebarTabRegistry = <SidebarTabDescriptor>[
  SidebarTabDescriptor(
    id: SidebarTabId.chats,
    labelBuilder: _chatsLabel,
    searchHintBuilder: _conversationSearchHint,
    bodyBuilder: _chatsBody,
    materialIcon: Icons.chat_bubble_outline,
    selectedMaterialIcon: Icons.chat_bubble,
    sfSymbol: 'bubble.left',
    selectedSfSymbol: 'bubble.left.fill',
    isVisible: _chatsVisible,
    createAction: chatSidebarCreateAction,
  ),
  SidebarTabDescriptor(
    id: SidebarTabId.notes,
    labelBuilder: _notesLabel,
    searchHintBuilder: _notesSearchHint,
    bodyBuilder: _notesBody,
    materialIcon: Icons.note_outlined,
    selectedMaterialIcon: Icons.note,
    sfSymbol: 'doc.text',
    selectedSfSymbol: 'doc.text.fill',
    isVisible: _notesVisible,
    createAction: noteSidebarCreateAction,
  ),
  SidebarTabDescriptor(
    id: SidebarTabId.channels,
    labelBuilder: _channelsLabel,
    searchHintBuilder: _channelsSearchHint,
    bodyBuilder: _channelsBody,
    materialIcon: Icons.tag,
    selectedMaterialIcon: Icons.tag,
    sfSymbol: 'number',
    selectedSfSymbol: 'number',
    isVisible: _channelsVisible,
    createAction: channelSidebarCreateAction,
  ),
];

SidebarTabDescriptor sidebarTabDescriptor(SidebarTabId id) =>
    sidebarTabRegistry.firstWhere((descriptor) => descriptor.id == id);

List<SidebarTabId> visibleSidebarTabIds(SidebarTabAvailability availability) =>
    [
      for (final descriptor in sidebarTabRegistry)
        if (descriptor.isVisible(availability)) descriptor.id,
    ];
