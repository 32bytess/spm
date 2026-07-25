import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('build_tree/arrow_body_metrics.dart');
    expect(
      results,
      hasLength(3),
      reason: 'Expected 3 State<> subclasses in arrow_body_metrics fixture',
    );
  });

  group('expression-bodied build()', () {
    test(
      'arrow body returning const widget sets rootBuildReturnsConstWidget',
      () {
        final r = results.firstWhere(
          (r) => r.stateClassName == '_ArrowConstReturnExampleState',
        );
        expect(
          r.rootBuildReturnsConstWidget,
          isTrue,
          reason: '`=> const Text(...)` is a const root return',
        );
        expect(
          r.treeNonConstWidgetCount,
          equals(0),
          reason:
              'the only widget is const, so it is excluded from the '
              'non-const treeNonConstWidgetCount',
        );
        expect(r.treeConstWidgetCount, equals(1));
      },
    );

    test('arrow body delegating to a helper counts the helper', () {
      final r = results.firstWhere(
        (r) => r.stateClassName == '_ArrowHelperRootExampleState',
      );
      expect(
        r.helperReferenceCount,
        equals(1),
        reason: '`=> _body()` is a widget-returning helper invocation',
      );
      expect(
        r.helperWidgetCount,
        equals(3),
        reason: 'helper body builds Column + 2 Texts',
      );
      expect(
        r.helperMaxWidgetNestingDepth,
        equals(2),
        reason: 'Column > Text nesting inside the helper body',
      );
    });
  });

  group('const returns inside closures (depth guard)', () {
    test(
      'builder closures returning const do not set rootBuildReturnsConstWidget',
      () {
        final r = results.firstWhere(
          (r) => r.stateClassName == '_ClosureConstReturnExampleState',
        );
        expect(
          r.rootBuildReturnsConstWidget,
          isFalse,
          reason:
              'block- and arrow-bodied builder closures return const SizedBox, '
              'but build() itself returns a non-const Column',
        );
        expect(
          r.treeConstWidgetCount,
          equals(2),
          reason: 'the two const SizedBox instances are still counted',
        );
      },
    );
  });
}
