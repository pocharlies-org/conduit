import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/utils/model_sort_utils.dart';
import 'package:conduit/features/chat/widgets/model_selector_sheet.dart';
import 'package:conduit/l10n/app_localizations_en.dart';

void main() {
  group('sortModelsWithPinnedOrder', () {
    const models = [
      Model(id: 'alpha', name: 'Alpha'),
      Model(id: 'bravo', name: 'Bravo'),
      Model(id: 'charlie', name: 'Charlie'),
      Model(id: 'delta', name: 'Delta'),
    ];

    test('moves pinned models to the top in pinned order', () {
      final sorted = sortModelsWithPinnedOrder(models, ['charlie', 'alpha']);

      check(sorted.map((model) => model.id).toList())
          .deepEquals(['charlie', 'alpha', 'bravo', 'delta']);
    });

    test('ignores stale pinned ids and keeps unpinned order stable', () {
      final sorted = sortModelsWithPinnedOrder(models, ['missing', 'delta']);

      check(sorted.map((model) => model.id).toList())
          .deepEquals(['delta', 'alpha', 'bravo', 'charlie']);
    });

    test('deduplicates pinned ids using the first pinned position', () {
      final sorted = sortModelsWithPinnedOrder(models, [
        'bravo',
        'charlie',
        ' bravo ',
      ]);

      check(sorted.map((model) => model.id).toList())
          .deepEquals(['bravo', 'charlie', 'alpha', 'delta']);
    });
  });

  test('custom server reasoning effort uses its configured level name', () {
    check(reasoningEffortLabelForTest(AppLocalizationsEn(), 'vendor_ultra'))
        .equals('vendor_ultra');
  });
}
