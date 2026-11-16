import 'package:checks/checks.dart';
import 'package:conduit/features/profile/views/manage_accounts_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit_core/auth/openwebui_account_summaries.dart';
import 'package:conduit_core/models/openwebui_registry.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/openwebui_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _home = OpenWebUiServer(
  id: 'home',
  name: 'Home Lab',
  endpoints: [OpenWebUiEndpoint(id: 'home-lan', url: 'http://10.0.0.2:3000')],
);

final _work = OpenWebUiServer(
  id: 'work',
  name: '',
  endpoints: [OpenWebUiEndpoint(id: 'work-1', url: 'https://chat.corp.com')],
);

OpenWebUiAccountEntry _entry(
  String id, {
  required String name,
  OpenWebUiServer? server,
  String? email,
  bool isActive = false,
  bool hasSession = true,
}) => OpenWebUiAccountEntry(
  account: OpenWebUiAccount(
    id: id,
    serverId: (server ?? _home).id,
    userId: 'u-$id',
  ),
  server: server ?? _home,
  summary: OpenWebUiAccountSummary(name: name, email: email),
  isActive: isActive,
  hasSession: hasSession,
);

/// Reports every switch as one that needs a sign-in, as the accounts
/// controller does for an account without a session.
final class _SignInNeeded implements OpenWebUiAccountsController {
  final switched = <String>[];

  @override
  Future<OpenWebUiAccountChangeResult> switchTo(
    String accountId, {
    bool force = false,
  }) async {
    switched.add(accountId);
    return OpenWebUiAccountChangeResult.needsSignIn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late GoRouter router;

  Future<_SignInNeeded> pumpAccounts(
    WidgetTester tester,
    List<OpenWebUiAccountEntry> accounts,
  ) async {
    final controller = _SignInNeeded();
    Widget target(String name) => Text(name);
    router = GoRouter(
      initialLocation: Routes.accounts,
      routes: [
        GoRoute(
          path: Routes.accounts,
          name: RouteNames.accounts,
          builder: (_, _) => const ManageAccountsPage(),
        ),
        GoRoute(
          path: Routes.authentication,
          builder: (_, _) => target('sign in'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openWebUiAccountsProvider.overrideWith((ref) async => accounts),
          openWebUiAccountsControllerProvider.overrideWithValue(controller),
          reviewerModeProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  String location() => router.routerDelegate.currentConfiguration.uri.path;

  Finder inCard(String card, Finder finder) =>
      find.descendant(of: find.byKey(Key(card)), matching: finder);

  testWidgets('each server is a card of its accounts, the active one checked', (
    tester,
  ) async {
    await pumpAccounts(tester, [
      _entry('alex-home', name: 'Alex', email: 'alex@home.lan', isActive: true),
      _entry('sam-home', name: 'Sam', hasSession: false),
      _entry('alex-work', name: 'Alex L.', server: _work),
    ]);

    // The server leads its card, under its initials; its accounts follow.
    expect(inCard('accounts-server-home', find.text('Home Lab')), findsOne);
    expect(inCard('accounts-server-home', find.text('HL')), findsOne);
    expect(inCard('accounts-server-home', find.text('Alex')), findsOne);
    expect(
      inCard('accounts-server-home', find.text('alex@home.lan')),
      findsOne,
    );
    expect(inCard('accounts-server-home', find.text('Signed out')), findsOne);
    // Without a name, a server goes by its host.
    expect(
      inCard('accounts-server-work', find.text('chat.corp.com')),
      findsOne,
    );
    expect(inCard('accounts-server-work', find.text('C')), findsOne);

    expect(
      find.descendant(
        of: find.byKey(const Key('accounts-row-alex-home')),
        matching: find.bySemanticsLabel('Active'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('accounts-row-sam-home')),
        matching: find.bySemanticsLabel('Active'),
      ),
      findsNothing,
    );
  });

  testWidgets('the active account, signed in, is not switched to', (
    tester,
  ) async {
    final controller = await pumpAccounts(tester, [
      _entry('alex-home', name: 'Alex', isActive: true),
      _entry('sam-home', name: 'Sam'),
    ]);

    await tester.tap(find.byKey(const Key('accounts-row-alex-home')));
    await tester.pumpAndSettle();

    check(controller.switched).isEmpty();
    check(location()).equals(Routes.accounts);
  });

  // The page stays open once the active account's session expires, and its
  // row, marked signed out, sends the person back to the sign-in.
  testWidgets('the active account, signed out, opens its sign-in', (
    tester,
  ) async {
    final controller = await pumpAccounts(tester, [
      _entry('alex-home', name: 'Alex', isActive: true, hasSession: false),
      _entry('sam-home', name: 'Sam'),
    ]);
    expect(
      find.descendant(
        of: find.byKey(const Key('accounts-row-alex-home')),
        matching: find.text('Signed out'),
      ),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('accounts-row-alex-home')));
    await tester.pumpAndSettle();

    check(controller.switched).deepEquals(['alex-home']);
    check(location()).equals(Routes.authentication);
    expect(find.text('sign in'), findsOneWidget);
  });

  testWidgets('with no account saved, the page offers nothing to add', (
    tester,
  ) async {
    await pumpAccounts(tester, const []);

    expect(find.text('Accounts'), findsOne);
    expect(find.byKey(const Key('accounts-sign-out-all')), findsNothing);
  });

  testWidgets('with one account, Settings signs out of it, not this page', (
    tester,
  ) async {
    await pumpAccounts(tester, [
      _entry('alex-home', name: 'Alex', isActive: true),
    ]);
    expect(find.byKey(const Key('accounts-sign-out-all')), findsNothing);
  });

  testWidgets('signing out of every account is offered with several', (
    tester,
  ) async {
    await pumpAccounts(tester, [
      _entry('alex-home', name: 'Alex', isActive: true),
      _entry('sam-home', name: 'Sam'),
    ]);
    await tester.scrollUntilVisible(
      find.byKey(const Key('accounts-sign-out-all')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('accounts-sign-out-all')), findsOne);
  });
}
