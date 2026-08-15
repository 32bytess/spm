/*
integration test for helpers that return a COLLECTION of widgets
(List<Widget> _buildRows(), List<DropdownMenuItem<T>> _buildItems(),
Iterable<Widget> _labels()). The return type is not a Widget subtype, but the
body builds widgets on every rebuild, so it must be counted and analyzed.
A collection of non-widgets, and SDK collection plumbing (toList), must not.
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  AnalysisResultEntity byName(String scopeName) =>
      results.firstWhere((r) => r.scopeName == scopeName);

  setUpAll(() async {
    results = await getResultsForFixture('build_tree/helper_widget_lists.dart');
    expect(
      results,
      hasLength(4),
      reason: 'Expected 4 State<> subclasses in helper_widget_lists fixture',
    );
  });

  group('List<Widget> helper', () {
    test('is counted as a helper reference', () {
      expect(byName('_ListHelperExampleState').helperReferenceCount, equals(1));
    });

    test('its body is analyzed for helper widgets', () {
      expect(
        byName('_ListHelperExampleState').helperWidgetCount,
        equals(3),
        reason:
            '_buildRows -> Padding + Text + SizedBox (EdgeInsets value object '
            'excluded)',
      );
    });
  });

  group('List<WidgetSubtype> helper', () {
    test('is counted even though the element type is not Widget itself', () {
      expect(
        byName('_SubtypeListHelperExampleState').helperReferenceCount,
        equals(1),
      );
      expect(
        byName('_SubtypeListHelperExampleState').helperWidgetCount,
        equals(2),
        reason: '_buildItems -> DropdownMenuItem + Text',
      );
    });

    test('iteration inside the helper body surfaces', () {
      expect(
        byName('_SubtypeListHelperExampleState').treeIterationCount,
        equals(1),
        reason: 'the for-in loop in _buildItems must be visible',
      );
      expect(
        byName('_SubtypeListHelperExampleState').iterationWidgetCount,
        greaterThan(0),
        reason: 'widgets built per element are per-element cost',
      );
    });
  });

  group('Iterable<Widget> helper', () {
    test('is counted when spread into a children literal', () {
      expect(
        byName('_IterableHelperExampleState').helperReferenceCount,
        equals(1),
      );
      expect(
        byName('_IterableHelperExampleState').helperWidgetCount,
        equals(1),
        reason: '_labels -> Text',
      );
    });
  });

  group('collection of non-widgets', () {
    test('is data, not a helper', () {
      expect(
        byName('_ValueListExampleState').helperReferenceCount,
        equals(0),
        reason: 'List<String> carries no widget cost',
      );
      expect(byName('_ValueListExampleState').helperWidgetCount, equals(0));
    });
  });
}
