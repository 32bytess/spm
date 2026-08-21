import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('build_tree/loop_ops_metrics.dart');
    expect(
      results,
      hasLength(7),
      reason: 'Expected 7 State<> subclasses in loop_ops_metrics fixture',
    );
  });

  group('treeIterationCount: loops and O(N) collection ops', () {
    test('no loops and no O(N) ops leave the counter at zero', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_NoLoopsNoOpsExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(0),
        reason:
            'No loops or O(N) ops in build should yield treeIterationCount=0',
      );
    });

    test('single for-in loop counts as one linear op', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_SingleForLoopExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(1),
        reason: 'One for loop should yield treeIterationCount=1',
      );
    });

    test('while + do-while each count as one linear op', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_WhileAndDoWhileExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(2),
        reason: 'One while + one do-while should yield treeIterationCount=2',
      );
    });

    test('sort + where + map each count as one linear op', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_LinearOpsOnlyExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(3),
        reason: 'sort + where + map should yield treeIterationCount=3',
      );
    });

    test('for loop + forEach + reduce counts all three', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_MixedLoopsAndOpsExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(3),
        reason: 'for loop + forEach + reduce should yield treeIterationCount=3',
      );
    });

    test('nested loops still count flat (one per construct)', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_NestedForLoopExampleState',
      );
      expect(
        r.treeIterationCount,
        equals(2),
        reason: 'for-in-for should yield treeIterationCount=2',
      );
    });
  });

  group('treeMaxIterationNestingDepth: nested vs sequential iteration', () {
    test('no iteration constructs leave the depth at zero', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_NoLoopsNoOpsExampleState',
      );
      expect(r.treeMaxIterationNestingDepth, equals(0));
    });

    test('a single loop gives a depth of one', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_SingleForLoopExampleState',
      );
      expect(r.treeMaxIterationNestingDepth, equals(1));
    });

    test('sequential loops do not stack, so the depth stays one', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_WhileAndDoWhileExampleState',
      );
      expect(
        r.treeMaxIterationNestingDepth,
        equals(1),
        reason: 'while followed by do-while is sequential, not nested',
      );
    });

    test('chained collection ops do not stack, so the depth stays one', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_LinearOpsOnlyExampleState',
      );
      expect(
        r.treeMaxIterationNestingDepth,
        equals(1),
        reason: 'sort/where/map on separate receivers run once each',
      );
    });

    test('a for inside a for gives a depth of two', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_NestedForLoopExampleState',
      );
      expect(
        r.treeMaxIterationNestingDepth,
        equals(2),
        reason: 'a loop in a loop body is O(N*M) nesting',
      );
    });

    test('a collection op inside a map callback gives a depth of two', () {
      final r = results.firstWhere(
        (r) => r.scopeName == '_NestedCollectionOpExampleState',
      );
      expect(
        r.treeMaxIterationNestingDepth,
        equals(2),
        reason:
            '.where inside a .map callback runs per element; the chained '
            'second .map must not raise depth further',
      );
      expect(
        r.treeIterationCount,
        equals(3),
        reason: 'map + where + chained map should yield treeIterationCount=3',
      );
    });
  });
}
