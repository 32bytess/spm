import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  group('treeListRenderingStrategy', () {
    late List<AnalysisResultEntity> results;

    setUpAll(() async {
      results = await getResultsForFixture(
        'contextual_heuristics/list_view_builder.dart',
      );
      expect(
        results,
        hasLength(3),
        reason: 'Expected 3 State<> subclasses in list_view_builder fixture',
      );
    });

    test('ListView.builder is lazy (1)', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_ListViewBuilderExampleState',
      );
      expect(r.treeListRenderingStrategy, equals(1));
    });

    test('plain ListView with mapped children is eager (2)', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_ListViewNoBuilderExampleState',
      );
      expect(
        r.treeListRenderingStrategy,
        equals(2),
        reason:
            'a concrete children: list on ListView builds every child on '
            'every rebuild — the eager O(N) case the old boolean missed',
      );
    });

    test('GridView.builder is lazy (1)', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_GridViewBuilderExampleState',
      );
      expect(r.treeListRenderingStrategy, equals(1));
    });
  });

  group('usesLayoutDependentBuilder', () {
    late List<AnalysisResultEntity> results;

    setUpAll(() async {
      results = await getResultsForFixture(
        'contextual_heuristics/layout_builder.dart',
      );
      expect(
        results,
        hasLength(2),
        reason: 'Expected 2 State<> subclasses in layout_builder fixture',
      );
    });

    test('LayoutBuilder sets the flag', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_WithLayoutBuilderExampleState',
      );
      expect(r.usesLayoutDependentBuilder, isTrue);
    });

    test('layout-independent build does not set the flag', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_WithoutLayoutBuilderExampleState',
      );
      expect(r.usesLayoutDependentBuilder, isFalse);
    });
  });
}
