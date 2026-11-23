import 'package:flutter/services.dart' show rootBundle;

import 'package:conduit_core/services/openwebui_seed.dart';

/// Installs the seed-accounts reader for this build: the asset ships inside
/// the package, so its bundle key carries the `packages/` prefix (OWU-157).
void installHomeSeed() {
  OpenWebUiSeed.installLoader(
    () => rootBundle.loadString(
      'packages/conduit_home/assets/seed_accounts.json',
    ),
  );
}
