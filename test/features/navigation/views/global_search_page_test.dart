import 'package:conduit_core/models/workspace_search.dart';
import 'package:conduit/features/navigation/providers/workspace_search_providers.dart';
import 'package:conduit/features/navigation/views/global_search_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The global search page groups what `GET /api/v1/search` answers by kind,
/// narrows it with the kind filters, and says so when there is nothing or the
/// search could not run.
void main() {
  final page = WorkspaceSearchResults(
    hits: [
      _hit('c1', WorkspaceSearchKind.chat, 'Budget talk'),
      _hit('m7', WorkspaceSearchKind.message, 'Message seven'),
      _hit('n3', WorkspaceSearchKind.note, 'Q4 budget'),
    ],
    kinds: WorkspaceSearchKind.values,
  );

  testWidgets('results render grouped under their kind', (tester) async {
    await tester.pumpWidget(_harness(page));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Notes'), findsWidgets);
    expect(find.text('Budget talk'), findsOneWidget);
    expect(find.text('Message seven'), findsOneWidget);
    expect(find.text('Q4 budget'), findsOneWidget);
  });

  testWidgets('a kind filter narrows the list and clearing it restores it', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(page));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Q4 budget'), findsOneWidget);
    expect(find.text('Budget talk'), findsNothing);
    expect(find.text('Message seven'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pumpAndSettle();

    expect(find.text('Budget talk'), findsOneWidget);
    expect(find.text('Message seven'), findsOneWidget);
    expect(find.text('Q4 budget'), findsOneWidget);
  });

  testWidgets('no hits says so instead of an empty page', (tester) async {
    await tester.pumpWidget(
      _harness(const WorkspaceSearchResults(kinds: [WorkspaceSearchKind.chat])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('a failed search says so and offers a retry', (tester) async {
    await tester.pumpWidget(_harness(null, error: StateError('down')));
    await tester.pumpAndSettle();

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

WorkspaceSearchHit _hit(
  String id,
  WorkspaceSearchKind kind,
  String title,
) => WorkspaceSearchHit(
  id: id,
  kind: kind,
  title: title,
  context: 'context',
  snippet: 'snippet of $id',
  url: switch (kind) {
    WorkspaceSearchKind.chat => '/c/$id',
    WorkspaceSearchKind.message => '/channels/ch9?message=$id',
    WorkspaceSearchKind.note => '/notes/$id',
  },
);

Widget _harness(WorkspaceSearchResults? results, {Object? error}) {
  return ProviderScope(
    overrides: [
      workspaceSearchResultsProvider.overrideWith((ref) async {
        if (error != null) throw error;
        return results;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light(TweakcnThemes.t3Chat),
      localizationsDelegates: conduitLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GlobalSearchPage(),
    ),
  );
}