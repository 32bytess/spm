/*
integration test for the rebuild-path scoping rule: code that only runs on
user interaction is not rebuild cost, so it stays out of every tree feature.
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    final all = await getResultsForFixture('build_tree');
    results = all
        .where((r) => r.filePath.contains('handler_callbacks'))
        .toList();
    expect(
      results,
      isNotEmpty,
      reason: 'No analysis results found for handler_callbacks fixture.',
    );
  });

  AnalysisResultEntity scope(String name) =>
      results.firstWhere((r) => r.scopeName == name);

  group('event handler bodies are not rebuild cost', () {
    test('control flow inside onPressed does not raise complexity', () {
      final r = scope('_HandlerComplexityExampleState');
      expect(
        r.treeCyclomaticComplexity,
        equals(1),
        reason:
            'the if and the && live in onPressed, which the traced rebuild '
            'window never runs',
      );
    });

    test('widgets built inside a handler are not counted', () {
      final r = scope('_HandlerWidgetExampleState');
      expect(
        r.treeNonConstWidgetCount,
        equals(2),
        reason:
            'TextButton + Text; the dialog Container/Column/Text are not '
            'built by a rebuild',
      );
      expect(
        r.treeMaxWidgetNestingDepth,
        equals(2),
        reason: 'the dialog subtree adds no depth to this scope',
      );
      expect(
        r.treeConstWidgetCount,
        equals(0),
        reason: 'the const Divider sits inside the handler',
      );
      expect(
        r.valueObjectAllocCount,
        equals(0),
        reason: 'the EdgeInsets is allocated on press, not on rebuild',
      );
    });

    test('a page pushed from a handler does not merge its tree', () {
      final r = scope('_HandlerNavigationExampleState');
      expect(
        r.treeNonConstWidgetCount,
        equals(2),
        reason:
            'TextButton + Text; _PushedPage is a whole other screen and this '
            'rebuild never renders it',
      );
      expect(
        r.walkedWidgetClasses.where((c) => c.contains('_PushedPage')),
        isEmpty,
        reason: 'the child traversal must not be seeded from a handler closure',
      );
      expect(
        r.valueObjectAllocCount,
        equals(0),
        reason: 'the MaterialPageRoute is allocated on press',
      );
    });

    test(
      'a local function reached only from a handler contributes nothing',
      () {
        final r = scope('_HandlerLocalFnExampleState');
        expect(
          r.treeNonConstWidgetCount,
          equals(2),
          reason:
              'badge() is called from the dialog builder inside onPressed, so '
              'its Container and Text are not rebuild cost, and deferring its '
              'body must not resurrect it at the root either',
        );
      },
    );

    test('a handler tear-off does not pull in the torn-off body', () {
      final r = scope('_HandlerTearOffExampleState');
      expect(
        r.treeNonConstWidgetCount,
        equals(2),
        reason: 'onPressed: submit is a call site that fires on interaction',
      );
      expect(
        r.valueObjectAllocCount,
        equals(0),
        reason: 'the EdgeInsets inside submit is allocated on press',
      );
    });
  });

  group('builder callbacks are still build work', () {
    test('named and positional builders contribute as before', () {
      final r = scope('_BuilderCallbacksExampleState');
      expect(
        r.treeNonConstWidgetCount,
        equals(9),
        reason:
            'Column, LayoutBuilder + its Text, SizedBox, ListView, the '
            'itemBuilder Padding + Text, and Obx + its Text',
      );
      expect(
        r.treeMaxWidgetNestingDepth,
        equals(5),
        reason: 'Column > SizedBox > ListView > Padding > Text',
      );
      expect(
        r.iterationWidgetCount,
        equals(2),
        reason: 'the itemBuilder body runs once per visible element',
      );
    });

    test('a positional builder callback is still its own scope', () {
      expect(
        results.where((r) => r.scopeName == 'Obx_builder'),
        hasLength(1),
        reason: 'Obx(() => ...) is a rebuild scope of its own',
      );
    });
  });
}
