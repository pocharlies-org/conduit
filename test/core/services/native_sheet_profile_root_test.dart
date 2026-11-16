import 'package:checks/checks.dart';
import 'package:conduit/core/services/native_sheet_bridge.dart';
import 'package:conduit/core/utils/native_sheet_utils.dart';
import 'package:conduit/features/navigation/widgets/sidebar_user_pill.dart'
    show nativeProfileSheetFieldsDiffer;
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit_core/auth/openwebui_account_summaries.dart';
import 'package:conduit_core/models/account_metadata.dart';
import 'package:conduit_core/models/openwebui_registry.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

const _account = NativeProfileRootAccount(
  displayName: 'Ada',
  email: 'ada@example.com',
);

const _card = (title: 'Ada', subtitle: 'Home Lab +1');

const _everything = NativeProfileRootVisibility(
  showCalendar: true,
  canManageWorkspace: true,
  showScheduledTasks: true,
  showPersonalConnections: true,
  showChatDataControls: true,
);

final _home = OpenWebUiServer(
  id: 'home',
  name: 'Home Lab',
  endpoints: [OpenWebUiEndpoint(id: 'home-lan', url: 'http://10.0.0.2:3000')],
);

OpenWebUiAccountEntry _entry(
  String id,
  OpenWebUiServer server, {
  required String name,
  String? email,
  String? profileImage,
  bool isActive = false,
  bool hasSession = true,
}) => OpenWebUiAccountEntry(
  account: OpenWebUiAccount(id: id, serverId: server.id),
  server: server,
  summary: OpenWebUiAccountSummary(
    name: name,
    email: email,
    profileImage: profileImage,
  ),
  isActive: isActive,
  hasSession: hasSession,
);

List<List<String>> _ids(List<NativeSheetSectionConfig> sections) => [
  for (final section in sections) [for (final item in section.items) item.id],
];

NativeSheetItemConfig _item(
  List<NativeSheetSectionConfig> sections,
  String id,
) => sections
    .expand((section) => section.items)
    .singleWhere((item) => item.id == id);

List<NativeSheetSectionConfig> _root({
  NativeProfileRootAccount? account = _account,
  NativeProfileRootVisibility visibility = const NativeProfileRootVisibility(),
  int? otherAccountCount = 0,
}) => buildNativeProfileRootSections(
  _l10n,
  account: account,
  visibility: visibility,
  card: _card,
  otherAccountCount: otherAccountCount,
);

void main() {
  group('native Settings root', () {
    test('Advanced rows use their own symbols and close the sheet', () {
      final sections = _root(visibility: _everything);

      final expected = {
        NativeSheetRoutes.scheduledTasks: 'clock.arrow.circlepath',
        NativeSheetRoutes.personalConnections: 'server.rack',
        NativeSheetRoutes.chatDataControls: 'externaldrive',
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        final item = _item(sections, key);
        expect(item.sfSymbol, value, reason: key);
        expect(item.dismissOnSelect, isTrue, reason: key);
        expect(item.actionId, key, reason: key);
      }
    });

    test('the Advanced and places groups go with their last row', () {
      final sections = _root();

      expect(
        sections.map((section) => section.title),
        isNot(contains(_l10n.advancedFeatures)),
      );
      final ids = _ids(sections).expand((ids) => ids).toList();
      expect(ids, isNot(contains(NativeSheetRoutes.calendar)));
      expect(ids, isNot(contains(NativeSheetRoutes.workspace)));
      expect(ids, isNot(contains(NativeSheetRoutes.scheduledTasks)));
      // Only the account's and support titles remain as section headings.
      expect(
        sections.where((section) => section.title != null).map((s) => s.title),
        [_l10n.accountSettingsTitle, _l10n.supportConduit],
      );
    });

    test('with several accounts, Sign out leaves only the active one', () {
      final sections = _root(otherAccountCount: 1);

      final signOut = _ids(sections)
          .firstWhere((ids) => ids.contains(nativeAccountSignOutActionId));
      expect(signOut, [nativeAccountSignOutActionId]);
      expect(
        _item(sections, nativeAccountSignOutActionId).title,
        _l10n.signOut,
      );
    });

    // The sheet reads the saved accounts as it opens. When that read failed
    // or ran late, the row said "Sign out" while it signed out of every
    // account.
    test('with the other accounts unknown, signing out says it signs out '
        'of all of them', () {
      final sections = _root(otherAccountCount: null);

      check(_item(sections, nativeSignOutActionId).title)
          .equals(_l10n.accountsSignOutAll);
      final ids = _ids(sections).expand((ids) => ids);
      check(ids.contains(nativeAccountSignOutActionId)).isFalse();
    });

    test('with one account, signing out is what it always was', () {
      final sections = _root();

      final ids = _ids(sections).expand((ids) => ids).toList();
      expect(ids, isNot(contains(nativeAccountSignOutActionId)));
      expect(_item(sections, nativeSignOutActionId).title, _l10n.signOut);
    });
  });

  group('native Accounts page', () {
    NativeSheetDetailConfig accountsPage({
      List<OpenWebUiAccountEntry>? accounts = const [],
    }) => buildNativeAccountsDetail(_l10n, accounts: accounts);

    // A switch left the active account signed out: it is switched to again,
    // which opens its sign-in.
    test('the active account, signed out, is switched to', () {
      final page = accountsPage(
        accounts: [
          _entry(
            'alex-home',
            _home,
            name: 'Alex',
            isActive: true,
            hasSession: false,
          ),
        ],
      );

      final active = _item(
        page.sections,
        '$nativeAccountSwitchActionId:alex-home',
      );
      expect(active.checked, isTrue);
      expect(active.actionId, nativeAccountSwitchActionId);
    });

    test('an uploaded picture travels with its account', () {
      final page = accountsPage(
        accounts: [
          _entry(
            'alex-home',
            _home,
            name: 'Alex',
            profileImage: 'data:image/png;base64,AQID',
          ),
        ],
      );

      expect(
        _item(
          page.sections,
          '$nativeAccountSwitchActionId:alex-home',
        ).avatarBytes,
        [1, 2, 3],
      );
    });

    test('signing out of every account is offered with several', () {
      expect(
        _ids(
          accountsPage(accounts: [_entry('alex-home', _home, name: 'Alex')])
              .sections,
        ).expand((ids) => ids),
        isNot(contains(nativeSignOutActionId)),
      );

      final page = accountsPage(
        accounts: [
          _entry('alex-home', _home, name: 'Alex', isActive: true),
          _entry('sam-home', _home, name: 'Sam'),
        ],
      );
      expect(_ids(page.sections).last, [nativeSignOutActionId]);
      expect(
        _item(page.sections, nativeSignOutActionId).title,
        _l10n.accountsSignOutAll,
      );
    });
  });

  test('About rows that open Flutter pages close the sheet with a chevron', () {
    final items = buildNativeAboutItems(_l10n, appVersion: '1.0');

    for (final id in [
      NativeSheetRoutes.releaseNotesManual,
      NativeSheetRoutes.openSourceLicenses,
    ]) {
      final item = items.singleWhere((item) => item.id == id);
      expect(item.dismissOnSelect, isTrue, reason: id);
      expect(item.showsDisclosure, isTrue, reason: id);
    }
  });

  group('Webhook destinations row', () {
    test('counts the destinations', () {
      String? subtitle(int? count) =>
          buildNativeNotificationTargetsItem(_l10n, count: count).subtitle;

      expect(subtitle(0), 'None');
      expect(subtitle(1), '1 destination');
      expect(subtitle(3), '3 destinations');
      expect(subtitle(null), isNull);
    });

    test('explains destinations in its group footer', () {
      final section = buildNativeNotificationTargetsSection(_l10n, count: 2);

      expect(section.footer, _l10n.notificationTargetsDescription);
      final item = section.items.single;
      expect(item.sfSymbol, 'bell.and.waves.left.and.right');
      expect(item.dismissOnSelect, isTrue);
      expect(item.actionId, nativeNotificationTargetsActionId);
    });
  });

  test('profile page rows show the About text, or Not set', () {
    AccountMetadata profile(String? bio) => AccountMetadata(
      id: 'user-1',
      email: 'ada@example.com',
      name: 'Ada',
      role: 'user',
      isActive: true,
      bio: bio,
    );
    NativeSheetItemConfig row(AccountMetadata? profile, String id) => _item(
      buildNativeProfileDetailSections(
        _l10n,
        displayName: 'Ada',
        accountProfile: profile,
      ),
      id,
    );

    expect(row(profile(' Hello '), 'profile-name').subtitle, 'Ada · Hello');
    expect(row(profile(' Hello '), 'profile-about').subtitle, 'Hello');
    expect(row(profile(''), 'profile-name').subtitle, 'Ada');
    expect(row(null, 'profile-about').subtitle, _l10n.notSet);
  });

  test('a refreshed profile reaches the sheet only when an edited field '
      'changed', () {
    const shown = AccountMetadata(
      id: 'user-1',
      email: 'ada@example.com',
      name: 'Ada',
      role: 'user',
      isActive: true,
      bio: 'Hello',
      gender: 'female',
      dateOfBirth: '1990-01-01',
      profileImageUrl: '/avatar.png',
    );
    AccountMetadata copy({
      String? bio = 'Hello',
      String? gender = 'female',
      String? dateOfBirth = '1990-01-01',
      String? profileImageUrl = '/avatar.png',
      String timezone = 'UTC',
    }) => AccountMetadata(
      id: 'user-1',
      email: 'ada@example.com',
      name: 'Ada',
      role: 'user',
      isActive: true,
      bio: bio,
      gender: gender,
      dateOfBirth: dateOfBirth,
      profileImageUrl: profileImageUrl,
      timezone: timezone,
    );

    expect(nativeProfileSheetFieldsDiffer(shown, copy()), isFalse);
    expect(
      nativeProfileSheetFieldsDiffer(shown, copy(timezone: 'CET')),
      isFalse,
    );
    expect(nativeProfileSheetFieldsDiffer(shown, copy(bio: 'New')), isTrue);
    expect(nativeProfileSheetFieldsDiffer(shown, copy(gender: null)), isTrue);
    expect(
      nativeProfileSheetFieldsDiffer(shown, copy(dateOfBirth: '1991-01-01')),
      isTrue,
    );
    expect(
      nativeProfileSheetFieldsDiffer(shown, copy(profileImageUrl: '/new.png')),
      isTrue,
    );
  });
}
