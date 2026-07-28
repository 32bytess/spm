import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('build_tree/cross_class_scopes.dart');
    expect(
      results,
      hasLength(4),
      reason: 'Expected 4 State<> subclasses in cross_class_scopes fixture',
    );
  });

  group('metrics composed across custom child widget classes', () {
    late AnalysisResultEntity crossClass;

    setUpAll(() {
      crossClass = results.firstWhere(
        (r) => r.scopeName == '_CrossClassExampleState',
      );
    });

    test('treeCyclomaticComplexity sums root and child build bodies', () {
      expect(
        crossClass.treeCyclomaticComplexity,
        equals(3),
        reason: 'root build has no branching (1) + child build has one if (2)',
      );
    });

    test('treeMaxWidgetNestingDepth composes usage depth with child depth', () {
      expect(
        crossClass.treeMaxWidgetNestingDepth,
        equals(5),
        reason:
            '_BranchingChild instantiated at depth 2 (Padding > child), its '
            'build reaches internal depth 3 (LayoutBuilder > SizedBox > Text) '
            '→ absolute depth 2 + 3 = 5',
      );
    });

    test('usesLayoutDependentBuilder is ORed across the whole tree', () {
      expect(
        crossClass.usesLayoutDependentBuilder,
        isTrue,
        reason:
            'the LayoutBuilder lives in the child build, not the root build',
      );
    });

    test('treeNonConstWidgetCount spans root and child builds', () {
      expect(
        crossClass.treeNonConstWidgetCount,
        equals(5),
        reason:
            'root: Padding + _BranchingChild = 2 (EdgeInsets value object '
            'excluded); child: LayoutBuilder + SizedBox + Text = 3',
      );
    });
  });

  group('helper-body cost signals merge into build metrics', () {
    late AnalysisResultEntity helperScope;

    setUpAll(() {
      helperScope = results.firstWhere(
        (r) => r.scopeName == '_HelperIterationScopeExampleState',
      );
    });

    test('treeIterationCount includes loops inside helper bodies', () {
      expect(
        helperScope.treeIterationCount,
        equals(3),
        reason:
            'the .map in build (1) + the two for loops in _grid() (2); helper '
            'bodies execute during build and contribute their iterations',
      );
    });

    test('treeMaxIterationNestingDepth includes helper bodies', () {
      expect(
        helperScope.treeMaxIterationNestingDepth,
        equals(2),
        reason:
            'the nested for-in-for inside _grid() sets the max even though '
            'build itself only reaches depth 1 via .map',
      );
    });

    test('treeCyclomaticComplexity includes helper-body decision points', () {
      expect(
        helperScope.treeCyclomaticComplexity,
        equals(3),
        reason:
            'build has no branching (1); the two for loops in _grid() add '
            'their decision points (+2) without re-adding the +1 base',
      );
    });

    test('treeListRenderingStrategy sees eager lists inside helper bodies', () {
      expect(
        helperScope.treeListRenderingStrategy,
        equals(2),
        reason:
            'build spreads into Row children (eager) and _grid() feeds Column '
            'a runtime-length variable — both are the eager O(N) case',
      );
    });
  });

  group('helper → helper chains', () {
    late AnalysisResultEntity transitive;

    setUpAll(() {
      transitive = results.firstWhere(
        (r) => r.scopeName == '_TransitiveHelperExampleState',
      );
    });

    test('helperWidgetCount follows transitive helper calls', () {
      expect(
        transitive.helperWidgetCount,
        equals(3),
        reason: '_outer builds Column (1), _inner builds Row + Text (2)',
      );
    });

    test('helperReferenceCount only counts build-body call sites', () {
      expect(
        transitive.helperReferenceCount,
        equals(1),
        reason:
            'build calls _outer() once; _outer calling _inner() is a '
            'helper-body call site and must not be counted',
      );
    });

    test('helperMaxWidgetNestingDepth spans chained helper bodies', () {
      expect(
        transitive.helperMaxWidgetNestingDepth,
        equals(2),
        reason: '_inner reaches Row > Text = 2; _outer only reaches 1',
      );
    });
  });

  test('tree depth composes each custom-child placement exactly once', () {
    final depthChain = results.firstWhere(
      (r) => r.scopeName == '_DepthChainExampleState',
    );

    expect(
      depthChain.treeMaxWidgetNestingDepth,
      equals(3),
      reason: '_DepthMiddle > _DepthLeaf > Text is exactly three levels',
    );
  });
}
