/*
integration test for invocation-free helper references: method tear-offs
(map(_buildRow)), explicit widget-returning getters, and top-level widget
functions must be counted and their bodies analyzed; plain widget fields
(synthetic getters) must not.
*/
import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  AnalysisResultEntity byName(String stateClassName) =>
      results.firstWhere((r) => r.stateClassName == stateClassName);

  setUpAll(() async {
    results = await getResultsForFixture('build_tree/helper_refs.dart');
    expect(
      results,
      hasLength(4),
      reason: 'Expected 4 State<> subclasses in helper_refs fixture',
    );
  });

  group('method tear-off (items.map(_buildRow))', () {
    test('is counted as a helper reference', () {
      expect(byName('_TearOffExampleState').helperReferenceCount, equals(1));
    });

    test('its body is analyzed for helper widgets', () {
      expect(
        byName('_TearOffExampleState').helperWidgetCount,
        equals(2),
        reason: '_buildRow -> Padding + Text (EdgeInsets value object excluded)',
      );
    });

    test('the mapped children remain the eager list case', () {
      expect(
        byName('_TearOffExampleState').treeListRenderingStrategy,
        equals(2),
      );
    });
  });

  group('explicit widget-returning getter', () {
    test('is counted as a helper reference', () {
      expect(
        byName('_GetterHelperExampleState').helperReferenceCount,
        equals(1),
      );
    });

    test('its body is analyzed for helper widgets', () {
      expect(
        byName('_GetterHelperExampleState').helperWidgetCount,
        equals(2),
        reason: '_header -> SizedBox + Text',
      );
    });
  });

  group('top-level widget function', () {
    test('is counted and resolved outside any class', () {
      expect(
        byName('_TopLevelFnExampleState').helperReferenceCount,
        equals(1),
      );
      expect(
        byName('_TopLevelFnExampleState').helperWidgetCount,
        equals(2),
        reason:
            'buildBanner -> DecoratedBox + Text (BoxDecoration value object '
            'excluded)',
      );
    });
  });

  group('plain widget field', () {
    test('is data, not a helper', () {
      expect(
        byName('_FieldWidgetExampleState').helperReferenceCount,
        equals(0),
        reason:
            'a field reference resolves to a synthetic getter and must not '
            'count as a helper',
      );
      expect(
        byName('_FieldWidgetExampleState').helperWidgetCount,
        equals(0),
      );
    });
  });
}
