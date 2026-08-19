/*
integration test for local-function attribution (a local function invoked
inside a loop is per-element cost, an unreferenced one is still counted) and
for rootBuildReturnsConstWidget, which must hold on EVERY exit rather than
being set by a single const early-return guard.
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
      'build_tree/local_fn_and_returns.dart',
    );
    expect(
      results,
      hasLength(4),
      reason: 'Expected 4 State<> subclasses in local_fn_and_returns fixture',
    );
  });

  group('local function invoked inside a loop', () {
    test('the loop is counted', () {
      expect(
        byName('_LocalFnInLoopExampleState').treeIterationCount,
        equals(1),
      );
    });

    test('its widgets are attributed to the per-element scope', () {
      expect(
        byName('_LocalFnInLoopExampleState').iterationWidgetCount,
        equals(2),
        reason:
            'row() builds Padding + Text once per element; counting the body '
            'at its declaration site would report 0 here',
      );
    });
  });

  test('a local function that is never referenced is still counted', () {
    expect(
      byName('_UnusedLocalFnExampleState').treeNonConstWidgetCount,
      equals(2),
      reason: 'Column + the SizedBox in the unreferenced local function',
    );
  });

  group('rootBuildReturnsConstWidget', () {
    test('a const early-exit guard does not make the build const', () {
      expect(
        byName('_GuardedConstReturnExampleState').rootBuildReturnsConstWidget,
        isFalse,
        reason:
            'the path that matters returns Column(children: [Text(...)]); '
            'only the loading guard is const',
      );
    });

    test('is true when every exit returns a const widget', () {
      expect(
        byName('_AllConstReturnsExampleState').rootBuildReturnsConstWidget,
        isTrue,
      );
    });
  });
}
