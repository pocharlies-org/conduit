import 'package:checks/checks.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit/features/web_shell/views/web_shell_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the shell stays inside the instance host and leaves for anything else', () {
    check(
      webShellIsInternal(
        'https://chat.lan.e-dani.com/c/1?x=2',
        'https://chat.lan.e-dani.com',
      ),
    ).isTrue();
    check(
      webShellIsInternal('https://otra.example/x', 'https://chat.lan.e-dani.com'),
    ).isFalse();
    check(webShellIsInternal('no-es-una-url', 'https://chat.lan.e-dani.com'))
        .isFalse();
  });

  testWidgets('without a server the shell says so instead of a blank page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWith((ref) => null)],
        child: MaterialApp(
          theme: AppTheme.light(TweakcnThemes.t3Chat),
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WebShellPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No server to open'), findsOneWidget);
  });
}
