/*
integration test for custom StatefulWidget children: a StatefulWidget has no
build() of its own — the extractor must resolve its State class (via the
createState() body, falling back to `extends State<W>`) and analyze that
build, its helpers, and its subtree.
*/
import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late AnalysisResultEntity host;

  setUpAll(() async {
    final results = await getResultsForFixture('build_tree/stateful_child.dart');
    host = results.firstWhere(
      (r) => r.stateClassName == '_StatefulChildHostState',
    );
  });

  test('treeNonConstWidgetCount includes the child State build()', () {
    expect(
      host.treeNonConstWidgetCount,
      equals(3),
      reason:
          'root: Column + CounterTile = 2; child State build: Container = 1. '
          'Before the fix the whole CounterTile subtree was invisible',
    );
  });

  test('treeMaxWidgetNestingDepth composes through the State class', () {
    expect(
      host.treeMaxWidgetNestingDepth,
      equals(3),
      reason:
          'CounterTile instantiated at depth 2, its State build adds '
          'Container (internal depth 1) → 2 + 1 = 3',
    );
  });

  test('helperReferenceCount includes the child State helpers', () {
    expect(
      host.helperReferenceCount,
      equals(2),
      reason: 'root build calls _title(); child State build calls _label()',
    );
  });

  test('helperWidgetCount spans root and child State helper bodies', () {
    expect(
      host.helperWidgetCount,
      equals(2),
      reason: '_title() -> Text (1) + _label() -> Text (1)',
    );
  });

  test('treeCyclomaticComplexity sums root and child State build bodies', () {
    expect(
      host.treeCyclomaticComplexity,
      equals(2),
      reason:
          'root build (1) + child State build (1); trivial helpers add no '
          'decision points',
    );
  });
}
