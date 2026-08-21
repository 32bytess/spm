/*
integration test for treeListRenderingStrategy (0 none / 1 lazy / 2 eager):
shape-based classification of the `children:` expression plus lazy list
constructors, aggregated as the max across build, helper, and child bodies.
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
      'contextual_heuristics/list_rendering.dart',
    );
    expect(
      results,
      hasLength(8),
      reason: 'Expected 8 State<> subclasses in list_rendering fixture',
    );
  });

  test('fixed-arity literal with an if-element stays 0', () {
    expect(
      byName('_FixedColumnExampleState').treeListRenderingStrategy,
      equals(0),
      reason:
          'an if-element is an O(1) branch; the child count does not scale '
          'with data size',
    );
  });

  test('spread inside the literal is eager (2)', () {
    expect(
      byName('_SpreadColumnExampleState').treeListRenderingStrategy,
      equals(2),
    );
  });

  test('collection-for element is eager (2)', () {
    expect(
      byName('_ForElementRowExampleState').treeListRenderingStrategy,
      equals(2),
    );
  });

  test('bare list variable as children is eager (2)', () {
    expect(
      byName('_VariableChildrenExampleState').treeListRenderingStrategy,
      equals(2),
      reason:
          'no iteration op appears anywhere, but children: rows is still '
          'runtime-length. The shape rule, not an op whitelist, must decide',
    );
  });

  test('SingleChildScrollView over a mapped Column is eager (2)', () {
    expect(
      byName('_ScrollViewColumnExampleState').treeListRenderingStrategy,
      equals(2),
      reason:
          'the old boolean missed this entirely: every child rebuilds with '
          'no viewport culling',
    );
  });

  test('SliverList is lazy (1)', () {
    expect(
      byName('_SliverListExampleState').treeListRenderingStrategy,
      equals(1),
    );
  });

  test('ListView.builder inside a helper body is seen (1)', () {
    expect(
      byName('_LazyHelperExampleState').treeListRenderingStrategy,
      equals(1),
      reason: 'helper bodies execute during build and contribute the signal',
    );
  });

  test('eager outranks lazy when both are present (max aggregation)', () {
    expect(
      byName('_EagerBeatsLazyExampleState').treeListRenderingStrategy,
      equals(2),
    );
  });
}
