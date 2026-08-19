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
      // 8 not 9, depth 5 not 6: the unresolved call is not recognised as a
      // widget, so it and its nesting level vanish. Comparing this row against
      // a resolved revision of the same scope would report a code change that
      // never happened.
      expect(scope.treeNonConstWidgetCount, 8);
      expect(scope.treeMaxWidgetNestingDepth, 5);
    });
  });
}
