/*
integration test for :
  - dependencyFiles
  - unresolvedDependencies
  - closureResolved

A rebuild scope's metrics are not a function of the file that declares it. The
extractor follows helpers across libraries and merges every custom child
widget's `build()` into the totals, so a row depends on a transitive closure of
files. Two things follow, and both are tested here:

  * mining commit history by "touched the declaring file" misses real edits;
  * a closure file that will not resolve makes the row WRONG rather than absent,
    and the scanned-file gate cannot see it, because that gate guards only the
    file being scanned.
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

AnalysisResultEntity screenScope(List<AnalysisResultEntity> results) =>
    results.firstWhere((r) => r.scopeName == '_ScreenState');

void main() {
  group('a resolved closure', () {
    late AnalysisResultEntity scope;

    setUpAll(() async {
      scope = screenScope(await getResultsForFixture('closure'));
    });

    test('reports the other file its metrics were computed from', () {
      expect(scope.filePath, endsWith('screen.dart'));
      expect(
        scope.dependencyFiles,
        containsAll(<Matcher>[endsWith('screen.dart'), endsWith('card.dart')]),
        reason:
            'card.dart defines the child widget whose build tree is merged '
            'into this row, so an edit there moves these metrics',
      );
    });

    test('declares itself complete', () {
      expect(scope.unresolvedDependencies, isEmpty);
      expect(scope.closureResolved, isTrue);
    });

    test('counts the child widget subtree', () {
      // Padding + MyCard + Container + Column + Text + Icon + Row + 2 Text.
      expect(scope.treeNonConstWidgetCount, 9);
      expect(scope.treeMaxWidgetNestingDepth, 6);
    });
  });

  group('a closure file that will not resolve', () {
    late AnalysisResultEntity scope;

    setUpAll(() async {
      scope = screenScope(await getResultsForFixture('closure_broken'));
    });

    test('still yields a row, because the declaring file is clean', () {
      // The whole point: the scanned-file gate passes. Without the closure
      // fields there is nothing on this row to suggest anything went wrong.
      expect(scope.filePath, endsWith('screen.dart'));
    });

    test('names the file it could not read', () {
      expect(scope.unresolvedDependencies, hasLength(1));
      expect(scope.unresolvedDependencies.single, endsWith('card.dart'));
      expect(scope.closureResolved, isFalse);
    });

    test('does not list an unreadable file as a dependency it used', () {
      expect(scope.dependencyFiles, isNot(contains(endsWith('card.dart'))));
    });

    test('has metrics silently short of the resolved case', () {
      // 2 not 9, depth 2 not 6: only `Padding` and `MyCard` from the scope's
      // own build survive, because the library that declares `MyCard` resolved
      // while carrying an error and is refused whole.
      //
      // Refusing it is the point. That library's types come back null, so its
      // widgets classify as value objects and its subtree is counted as
      // something it is not. Reading it produced a row of 8 that looked like a
      // measurement; refusing it produces a row of 2 that is short by an amount
      // `unresolvedDependencies` names. A short row a reader can see is worth
      // more than a wrong one they cannot, and comparing either against a
      // resolved revision of the same scope reports a code change that never
      // happened, which is why the field exists.
      expect(scope.treeNonConstWidgetCount, 2);
      expect(scope.treeMaxWidgetNestingDepth, 2);
    });
  });
}
