/*
integration test for the two literature-backed features added 2026-07-20:
 - iterationWidgetCount: non-const widgets built per element (loop bodies,
   collection-op callbacks, lazy-list builders) across build + helper bodies;
 - valueObjectAllocCount: non-const value-object allocations (EdgeInsets,
   TextStyle, ...) paid on every rebuild; const value objects excluded.
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  group('iterationWidgetCount', () {
    late List<AnalysisResultEntity> results;

    AnalysisResultEntity byName(String stateClassName) =>
        results.firstWhere((r) => r.stateClassName == stateClassName);

    setUpAll(() async {
      results = await getResultsForFixture('build_tree/iteration_widgets.dart');
      expect(
        results,
        hasLength(4),
        reason: 'Expected 4 State<> subclasses in iteration_widgets fixture',
      );
    });

    test('widgets inside a .map callback are per-element', () {
      final r = byName('_MapIterationExampleState');
      expect(
        r.iterationWidgetCount,
        equals(2),
        reason: 'Card + Text in the callback; Column and header Text are not',
      );
      expect(
        r.treeNonConstWidgetCount,
        equals(4),
        reason:
            'per-element widgets still count in the total (Column, header '
            'Text, Card, Text)',
      );
    });

    test('widgets inside a helper-body for loop are per-element', () {
      final r = byName('_LoopHelperIterationExampleState');
      expect(
        r.iterationWidgetCount,
        equals(2),
        reason:
            'SizedBox + Text inside the loop; the helper\'s Column is one-shot',
      );
    });

    test('widgets inside a lazy itemBuilder are per-element', () {
      final r = byName('_LazyBuilderIterationExampleState');
      expect(
        r.iterationWidgetCount,
        equals(2),
        reason:
            'ListTile + Text run per visible element; the ListView itself '
            'does not',
      );
    });

    test('fixed literal children are not per-element', () {
      expect(
        byName('_FlatConstValueObjectExampleState').iterationWidgetCount,
        equals(0),
      );
    });
  });

  group('valueObjectAllocCount', () {
    test('non-const value objects count, const ones are free', () async {
      final results = await getResultsForFixture(
        'build_tree/iteration_widgets.dart',
      );
      final r = results.firstWhere(
        (x) => x.stateClassName == '_FlatConstValueObjectExampleState',
      );
      expect(
        r.valueObjectAllocCount,
        equals(1),
        reason:
            'EdgeInsets.all(4) margin allocates every rebuild; the const '
            'EdgeInsets.all(8) padding is canonicalized',
      );
    });

    test(
      'all three non-const value objects in the value_objects fixture',
      () async {
        final results = await getResultsForFixture(
          'build_tree/value_objects.dart',
        );
        final r = results.firstWhere(
          (x) => x.stateClassName == '_ValueObjectExampleState',
        );
        expect(
          r.valueObjectAllocCount,
          equals(3),
          reason:
              'EdgeInsets.all + EdgeInsets.symmetric + TextStyle, all '
              'non-const — previously this signal was discarded entirely',
        );
      },
    );
  });
}
