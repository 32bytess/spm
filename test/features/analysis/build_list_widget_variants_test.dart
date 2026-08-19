/*
integration test for list widgets beyond ListView/GridView: ReorderableListView
and PageView are classified by their constructor, a sliver is classified by its
delegate, and List.generate is iteration rather than a lone allocation.
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  AnalysisResultEntity byName(String scopeName) =>
      results.firstWhere((r) => r.scopeName == scopeName);

  setUpAll(() async {
    results = await getResultsForFixture(
      'build_tree/list_widget_variants.dart',
    );
    expect(
      results,
      hasLength(5),
      reason: 'Expected 5 State<> subclasses in list_widget_variants fixture',
    );
  });

  group('ReorderableListView.builder', () {
    test('is lazy, like ListView.builder', () {
      expect(
        byName('_ReorderableLazyExampleState').treeListRenderingStrategy,
        equals(1),
      );
    });

    test('its itemBuilder widgets are per-element cost', () {
      expect(
        byName('_ReorderableLazyExampleState').iterationWidgetCount,
        greaterThan(0),
        reason: 'itemBuilder runs once per visible element',
      );
    });
  });

  test('PageView with a concrete children: list is eager', () {
    expect(
      byName('_EagerPageViewExampleState').treeListRenderingStrategy,
      equals(2),
    );
  });

  group('sliver delegates', () {
    test('SliverChildListDelegate is eager despite the sliver wrapper', () {
      expect(
        byName('_EagerSliverExampleState').treeListRenderingStrategy,
        equals(2),
        reason: 'a concrete child list is built in full on every rebuild',
      );
    });

    test('SliverChildBuilderDelegate stays lazy', () {
      expect(
        byName('_LazySliverExampleState').treeListRenderingStrategy,
        equals(1),
      );
    });
  });

  group('List.generate', () {
    test('counts as iteration', () {
      expect(byName('_GenerateExampleState').treeIterationCount, equals(1));
      expect(
        byName('_GenerateExampleState').treeMaxIterationNestingDepth,
        equals(1),
      );
    });

    test('its generated widgets are per-element cost', () {
      expect(
        byName('_GenerateExampleState').iterationWidgetCount,
        greaterThan(0),
        reason: 'the callback builds one Text per element, not one total',
      );
    });
  });
}
