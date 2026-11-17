import 'package:conduit_core/features/workspace/models/workspace_capabilities.dart';

// Route paths and names, shared by the router and the Flutter-free core.

/// Route path definitions used across the app.
class Routes {
  static const String splash = '/splash';
  static const String chat = '/chat';
  static const String folder = '/folder/:id';
  static const String connectionIssue = '/connection-issue';
  static const String authentication = '/authentication';
  static const String profile = '/profile';
  static const String personalization = '/profile/personalization';
  static const String audioSettings = '/profile/audio';
  static const String accountSettings = '/profile/account';
  static const String accounts = '/profile/accounts';
  static const String notificationSettings = '/profile/notifications';
  static const String appearanceSettings = '/profile/appearance';
  static const String chatSettings = '/profile/chat';
  static const String dataConnectionSettings = '/profile/data-connection';
  static const String personalConnections = '/profile/personal-connections';
  static const String personalConnectionEditor =
      '/profile/personal-connections/:kind/:identity';
  static const String chatDataControls = '/profile/chat-data-controls';
  static const String scheduledTasks = '/profile/scheduled-tasks';
  static const String scheduledTaskNew = '/profile/scheduled-tasks/new';
  static const String scheduledTaskDetail = '/profile/scheduled-tasks/:id';
  static const String scheduledTaskEdit = '/profile/scheduled-tasks/:id/edit';
  static const String calendar = '/profile/calendar';
  static const String images = '/profile/images';
  static const String about = '/profile/about';
  static const String notes = '/notes';
  static const String noteEditor = '/notes/:id';
  static const String channel = '/channel/:id';
  static const String workspace = '/workspace';

  static String folderPath(String id) => '/folder/$id';
}

/// Friendly names for GoRouter routes to support context.pushNamed.
class RouteNames {
  static const String splash = 'splash';
  static const String chat = 'chat';
  static const String folder = 'folder';
  static const String connectionIssue = 'connection-issue';
  static const String authentication = 'authentication';
  static const String profile = 'profile';
  static const String personalization = 'personalization';
  static const String audioSettings = 'audio-settings';
  static const String accountSettings = 'account-settings';
  static const String accounts = 'accounts';
  static const String notificationSettings = 'notification-settings';
  static const String appearanceSettings = 'appearance-settings';
  static const String chatSettings = 'chat-settings';
  static const String dataConnectionSettings = 'data-connection-settings';
  static const String personalConnections = 'personal-connections';
  static const String chatDataControls = 'chat-data-controls';
  static const String scheduledTasks = 'scheduled-tasks';
  static const String scheduledTaskNew = 'scheduled-task-new';
  static const String scheduledTaskDetail = 'scheduled-task-detail';
  static const String scheduledTaskEdit = 'scheduled-task-edit';
  static const String calendar = 'calendar';
  static const String images = 'images';
  static const String personalConnectionEditor = 'personal-connection-editor';
  static const String about = 'about';
  static const String notes = 'notes';
  static const String noteEditor = 'note-editor';
  static const String channel = 'channel';
  static const String workspace = 'workspace';
}

enum WorkspaceSection { models, knowledge, prompts, tools, skills }

enum WorkspaceRouteMode { collection, create, detail, edit }

class WorkspaceRouteDescriptor {
  const WorkspaceRouteDescriptor({required this.section});

  final WorkspaceSection section;

  String get segment => section.name;
  String get collectionPath => '/workspace/$segment';
  String get createPattern => '$collectionPath/create';
  String get detailPattern => '$collectionPath/:id';
  String get editPattern => '$collectionPath/:id/edit';
  String get collectionName => 'workspace-$segment';
  String get createName => 'workspace-$segment-create';
  String get detailName => 'workspace-${_singular(segment)}-detail';
  String get editName => 'workspace-${_singular(segment)}-edit';

  String detailLocation(String id) =>
      Uri(pathSegments: const ['', 'workspace'] + [segment, id]).toString();
  String editLocation(String id) =>
      Uri(pathSegments: const ['', 'workspace'] + [segment, id, 'edit'])
          .toString();

  static String _singular(String value) => switch (value) {
    'models' => 'model',
    'prompts' => 'prompt',
    'tools' => 'tool',
    'skills' => 'skill',
    _ => value,
  };
}

const workspaceRouteDescriptors = <WorkspaceRouteDescriptor>[
  WorkspaceRouteDescriptor(section: WorkspaceSection.models),
  WorkspaceRouteDescriptor(section: WorkspaceSection.knowledge),
  WorkspaceRouteDescriptor(section: WorkspaceSection.prompts),
  WorkspaceRouteDescriptor(section: WorkspaceSection.tools),
  WorkspaceRouteDescriptor(section: WorkspaceSection.skills),
];

// Keyed lookup so a section resolves to its descriptor by identity rather than
// by list position — inserting a new WorkspaceSection anywhere no longer risks
// silently returning the wrong descriptor.
final Map<WorkspaceSection, WorkspaceRouteDescriptor> _descriptorsBySection = {
  for (final descriptor in workspaceRouteDescriptors)
    descriptor.section: descriptor,
};

extension WorkspaceSectionX on WorkspaceSection {
  WorkspaceRouteDescriptor get routes => _descriptorsBySection[this]!;
  String get path => routes.collectionPath;

  WorkspaceSectionCapabilities capabilities(WorkspaceCapabilities value) {
    return switch (this) {
      WorkspaceSection.models => value.models,
      WorkspaceSection.knowledge => value.knowledge,
      WorkspaceSection.prompts => value.prompts,
      WorkspaceSection.tools => value.tools,
      WorkspaceSection.skills => value.skills,
    };
  }
}

const workspaceSectionOrder = <WorkspaceSection>[
  WorkspaceSection.models,
  WorkspaceSection.knowledge,
  WorkspaceSection.prompts,
  WorkspaceSection.tools,
  WorkspaceSection.skills,
];

List<WorkspaceSection> permittedWorkspaceSections(
  WorkspaceCapabilities capabilities,
) {
  return workspaceSectionOrder
      .where((section) => section.capabilities(capabilities).manage)
      .toList(growable: false);
}

WorkspaceSection? workspaceSectionForPath(String location) {
  final segments = Uri.tryParse(location)?.pathSegments;
  if (segments == null ||
      segments.length < 2 ||
      segments.first != 'workspace') {
    return null;
  }
  for (final descriptor in workspaceRouteDescriptors) {
    if (segments[1] == descriptor.segment) return descriptor.section;
  }
  return null;
}
